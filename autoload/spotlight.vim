scriptencoding utf-8
" autoload/spotlight.vim — core logic for vim-spotlight
" Source: https://github.com/arthurdaquinosilva/vim-spotlight
" License: MIT

let s:save_cpo = &cpoptions
set cpoptions&vim

" ── Model ────────────────────────────────────────────────────────────────────
"
" Spotlights live in b:spotlight, so they are per-buffer and disappear with
" the buffer. Shape:
"
"   regions  list of regions, in the order they were added
"   focus    0 to light every enabled region, or the id of the one region
"            lit on its own (<leader>hn / <leader>hb)
"   walk     after <leader>hd: region ids of the block and the blocks inside
"   lines    buffer line count when the regions were last updated
"   next_id  id for the next region
"
" Each region:
"
"   id       stable id; also the text property id in Vim
"   mode     'char' | 'line' | 'block'
"   pos      [sl, sc, el, ec]  1-based lines and byte columns; ec is exclusive
"                              (one past the last lit byte). Columns are
"                              ignored in 'line' mode.
"   vcols    [left, right]     'block' mode only: inclusive screen columns.
"                              right == 0 means "to the end of every line".
"   enabled  0 when switched off with <leader>hx (kept, but not lit)
"   anchor   text property id / extmark id that tracks pos across edits
"
" Everything outside the union of the lit regions is dimmed. When no region
" is lit (all switched off) nothing is dimmed, but the regions are kept.
"
" Matches are window-local, so every window showing the buffer gets its own
" copy. Windows that carry our matches are flagged with w:spotlight so the
" (cheap) autocmds in plugin/spotlight.vim know when there is work to do.

let s:maxcol = 2147483647
let s:has_nvim = has('nvim')
let s:has_textprop = !s:has_nvim && has('textprop')
let s:has_invalidate = has('nvim-0.10')
let s:end_row_key = has('nvim-0.6') ? 'end_row' : 'end_line'
let s:has_prop_find = s:has_textprop && exists('*prop_find')
let s:has_prop_range = s:has_textprop && has('patch-8.2.3652')
let s:prop_type = 'spotlight_anchor'
let s:ns = s:has_nvim ? nvim_create_namespace('spotlight') : 0
let s:cursor_events = ['CursorMoved', 'CursorMovedI', 'CursorHold', 'CursorHoldI']
let s:ei_added = []
let s:suppressing = 0
" :match highlights hidden while suppressing, by window ID.
let s:hidden_match = {}
let s:sweep_timer = -1
let s:sweep_interval = 100
let s:sweep_count = 50
let s:hls_hidden = 0
let s:hls_saved = 0
" Match groups of cursor-driven highlights: coc.nvim's document highlight and
" matching-pair highlights (vim-matchup, matchparen-style plugins).
let s:cursor_hl_groups = '^\%(CocHighlight\|MatchParen\|MatchWord\)'

" ── Small helpers ────────────────────────────────────────────────────────────

function! s:line_count(bufnr) abort
    if a:bufnr == bufnr('%')
        return line('$')
    endif
    let l:info = getbufinfo(a:bufnr)
    return empty(l:info) ? 1 : get(l:info[0], 'linecount',
        \ len(getbufline(a:bufnr, 1, '$')))
endfunction

function! s:priority() abort
    return get(g:, 'spotlight_priority', 100)
endfunction

" Byte length of the character that starts at (lnum, col), or 0 past the end.
function! s:char_len(lnum, col) abort
    return len(matchstr(getline(a:lnum), '\%' . a:col . 'c.'))
endfunction

" Screen column where the character at (lnum, col[, off]) starts / ends.
function! s:vcol_start(lnum, col, off) abort
    let l:before = a:col > 1 ? virtcol([a:lnum, a:col - 1]) : 0
    return l:before + 1 + a:off
endfunction

function! s:vcol_end(lnum, col, off) abort
    if a:col > len(getline(a:lnum))
        return s:vcol_start(a:lnum, a:col, a:off)
    endif
    return virtcol([a:lnum, a:col]) + a:off
endfunction

" ── Position anchors (track the regions while the buffer is edited) ──────────
"
" Vim: one multi-line text property per region, spanning it. Text properties
" move with inserted/deleted text, survive deletion of the first or last line
" (the remaining segments simply become the new edge) and are restored by
" undo. Neovim: one extmark with an end position per region. Without either,
" the regions stay at fixed coordinates.

function! s:anchor_set(bufnr, region) abort
    let [l:sl, l:sc, l:el, l:ec] = a:region.pos
    if s:has_nvim
        " Gravity mirrors Vim's start_incl/end_incl: typing at either edge of a
        " char-wise region extends it, while for line/block regions a line
        " opened right above the first line stays outside.
        let l:opts = {
            \ 'end_col': l:ec - 1,
            \ 'right_gravity': a:region.mode ==# 'char' ? v:false : v:true,
            \ 'end_right_gravity': v:true,
            \ }
        let l:opts[s:end_row_key] = l:el - 1
        if s:has_invalidate
            " Mark the extmark invalid (instead of collapsing it) when its
            " whole range is deleted, e.g. by :%! or :edit!.
            let l:opts.invalidate = v:true
        endif
        return nvim_buf_set_extmark(a:bufnr, s:ns, l:sl - 1, l:sc - 1, l:opts)
    elseif s:has_textprop
        if empty(prop_type_get(s:prop_type))
            call prop_type_add(s:prop_type, {'start_incl': 1, 'end_incl': 1})
        endif
        call prop_add(l:sl, l:sc, {
            \ 'type': s:prop_type,
            \ 'id': a:region.id,
            \ 'bufnr': a:bufnr,
            \ 'end_lnum': l:el,
            \ 'end_col': l:ec,
            \ })
        return a:region.id
    endif
    return 0
endfunction

" Remove one region's anchor.
function! s:anchor_del(bufnr, region) abort
    if !get(a:region, 'anchor', 0)
        return
    endif
    if s:has_nvim
        call nvim_buf_del_extmark(a:bufnr, s:ns, a:region.anchor)
    elseif s:has_textprop && !empty(prop_type_get(s:prop_type))
        call prop_remove({'type': s:prop_type, 'id': a:region.anchor,
            \ 'both': 1, 'bufnr': a:bufnr, 'all': 1}, 1, s:line_count(a:bufnr))
    endif
endfunction

" Remove every anchor in the buffer.
function! s:anchor_clear(bufnr) abort
    if s:has_nvim
        call nvim_buf_clear_namespace(a:bufnr, s:ns, 0, -1)
    elseif s:has_textprop && !empty(prop_type_get(s:prop_type))
        call prop_remove({'type': s:prop_type, 'bufnr': a:bufnr, 'all': 1},
            \ 1, s:line_count(a:bufnr))
    endif
endfunction

" Returns the anchored [sl, sc, el, ec] of {region}, or [] when the anchor is
" gone (for example after :edit! reloaded the file). {delta} is the change in
" the buffer's line count since the last refresh.
function! s:anchor_get(bufnr, region, delta) abort
    if !get(a:region, 'anchor', 0)
        return []
    endif
    if s:has_nvim
        let l:m = nvim_buf_get_extmark_by_id(a:bufnr, s:ns, a:region.anchor,
            \ {'details': v:true})
        if empty(l:m) || get(l:m[2], 'invalid', v:false)
            return []
        endif
        let [l:sl, l:sc] = [l:m[0] + 1, l:m[1] + 1]
        let l:end_row = get(l:m[2], 'end_row', get(l:m[2], 'end_line', l:m[0]))
        let [l:el, l:ec] = [l:end_row + 1, l:m[2].end_col + 1]
        " Deleting the region's last line leaves the end at column 0 of the
        " following line. The end only sits at column 0 of a non-empty line in
        " that case (typing extends it), so step back to the line above.
        if l:ec == 1 && l:el > l:sl && !empty(get(getbufline(a:bufnr, l:el), 0, ''))
            let l:el -= 1
            let l:ec = len(get(getbufline(a:bufnr, l:el), 0, '')) + 1
        endif
        return [l:sl, l:sc, l:el, l:ec]
    endif
    if !s:has_textprop
        return []
    endif

    " Fast path (this runs on every keystroke in Insert mode): an edit usually
    " leaves each edge where it was, or shifts it by the change in line count.
    " Only when neither guess holds is the buffer searched.
    let l:id = a:region.anchor
    let [l:osl, l:oel] = [a:region.pos[0], a:region.pos[2]]

    let l:first = s:segment_at(a:bufnr, l:id, [l:osl, l:osl + a:delta], 'start')
    if empty(l:first)
        let l:first = s:find_start(a:bufnr, l:id)
        if empty(l:first)
            return []
        endif
    endif
    let l:sl = l:first.lnum
    let l:sc = l:first.start ? l:first.col : 1

    let l:last = s:segment_at(a:bufnr, l:id,
        \ filter([l:oel, l:oel + a:delta], 'v:val >= l:sl'), 'end')
    if empty(l:last)
        let l:last = s:scan_to_end(a:bufnr, l:id, l:sl)
        if empty(l:last)
            return []
        endif
    endif
    let l:ec = l:last.col + l:last.length - (l:last.end ? 0 : 1)
    return [l:sl, l:sc, l:last.lnum, l:ec]
endfunction

function! s:is_ours(seg, id) abort
    return get(a:seg, 'type', '') ==# s:prop_type && get(a:seg, 'id', 0) == a:id
endfunction

" Property {id}'s segment on the first of {lnums} where it carries {flag}
" ('start' or 'end'), with 'lnum' added; {} when there is none.
function! s:segment_at(bufnr, id, lnums, flag) abort
    let l:total = s:line_count(a:bufnr)
    for l:lnum in a:lnums
        if l:lnum < 1 || l:lnum > l:total
            continue
        endif
        for l:seg in prop_list(l:lnum, {'bufnr': a:bufnr})
            if s:is_ours(l:seg, a:id) && l:seg[a:flag]
                return extend(l:seg, {'lnum': l:lnum})
            endif
        endfor
    endfor
    return {}
endfunction

" Slow path: the first segment of property {id} in the buffer.
function! s:find_start(bufnr, id) abort
    if s:has_prop_find
        return prop_find({'type': s:prop_type, 'id': a:id, 'both': 1,
            \ 'bufnr': a:bufnr, 'lnum': 1, 'col': 1}, 'f')
    endif
    for l:lnum in range(1, s:line_count(a:bufnr))
        for l:seg in prop_list(l:lnum, {'bufnr': a:bufnr})
            if s:is_ours(l:seg, a:id)
                return extend(l:seg, {'lnum': l:lnum})
            endif
        endfor
    endfor
    return {}
endfunction

" Slow path: walk from {from} to the segment that ends property {id}.
function! s:scan_to_end(bufnr, id, from) abort
    if s:has_prop_range
        let l:segs = prop_list(a:from, {'bufnr': a:bufnr, 'end_lnum': -1,
            \ 'types': [s:prop_type], 'ids': [a:id]})
        return empty(l:segs) ? {} : l:segs[-1]
    endif
    let l:last = {}
    let l:total = s:line_count(a:bufnr)
    let l:lnum = a:from
    while l:lnum <= l:total
        let l:segs = filter(prop_list(l:lnum, {'bufnr': a:bufnr}),
            \ 's:is_ours(v:val, a:id)')
        if empty(l:segs)
            break
        endif
        let l:last = extend(l:segs[-1], {'lnum': l:lnum})
        if l:last.end
            break
        endif
        let l:lnum += 1
    endwhile
    return l:last
endfunction

" ── Patterns ─────────────────────────────────────────────────────────────────
"
" Every lit region is broken into pieces that each cover a range of lines,
" either whole or within one column interval: a char-wise region gives its
" first line from the start column, its middle lines whole and its last line
" up to the end column; a block gives its lines between two screen columns.
" The lines are then cut into bands where the same pieces apply. A band with
" a whole-line piece stays lit, a band with no piece is dimmed entirely, and
" in any other band a character is dimmed when it is in none of the column
" intervals (negative lookaheads, so byte and screen columns can be mixed).

" The regions lit right now: the focused one, or every enabled one.
function! s:lit_regions(state) abort
    let l:focus = get(a:state, 'focus', 0)
    return filter(copy(a:state.regions),
        \ l:focus ? 'v:val.id == l:focus' : 'v:val.enabled')
endfunction

" Zero-width condition for byte columns [from, to) (to == 0: to end of line).
function! s:col_atom(from, to) abort
    return (a:from > 1 ? '\%>' . (a:from - 1) . 'c' : '')
        \ . (a:to > 0 ? '\%<' . a:to . 'c' : '')
endfunction

" Pieces of one region: [first line, last line, column atom], where the atom
" is '' for whole lines or a zero-width condition on the column.
function! s:pieces(region) abort
    let [l:sl, l:sc, l:el, l:ec] = a:region.pos
    if a:region.mode ==# 'line'
        return [[l:sl, l:el, '']]
    endif
    if a:region.mode ==# 'block'
        let [l:left, l:right] = a:region.vcols
        let l:atom = (l:left > 1 ? '\%>' . (l:left - 1) . 'v' : '')
            \ . (l:right > 0 ? '\%<' . (l:right + 1) . 'v' : '')
        return [[l:sl, l:el, l:atom]]
    endif
    if l:sl == l:el
        return l:ec > l:sc ? [[l:sl, l:sl, s:col_atom(l:sc, l:ec)]] : []
    endif
    let l:pieces = [[l:sl, l:sl, s:col_atom(l:sc, 0)]]
    if l:el > l:sl + 1
        call add(l:pieces, [l:sl + 1, l:el - 1, ''])
    endif
    if l:ec > 1
        call add(l:pieces, [l:el, l:el, s:col_atom(1, l:ec)])
    endif
    return l:pieces
endfunction

function! s:patterns(state) abort
    let l:pieces = []
    for l:region in s:lit_regions(a:state)
        call extend(l:pieces, s:pieces(l:region))
    endfor
    if empty(l:pieces)
        return []
    endif

    " Band edges: every line where a piece starts or ends.
    let l:edges = {}
    for [l:first, l:last, l:atom] in l:pieces
        let l:edges[l:first] = 1
        let l:edges[l:last + 1] = 1
    endfor
    let l:cuts = sort(map(keys(l:edges), 'str2nr(v:val)'), 'n')

    let l:pats = []
    if l:cuts[0] > 1
        call add(l:pats, '\%<' . l:cuts[0] . 'l.*')
    endif
    " Added even past the last line: if lines are appended from another
    " window or by a plugin, they are dimmed before the next refresh runs.
    call add(l:pats, '\%>' . (l:cuts[-1] - 1) . 'l.*')

    for l:i in range(len(l:cuts) - 1)
        let [l:first, l:last] = [l:cuts[l:i], l:cuts[l:i + 1] - 1]
        let l:atoms = []
        let l:whole = 0
        for [l:pfirst, l:plast, l:atom] in l:pieces
            if l:pfirst <= l:first && l:last <= l:plast
                if empty(l:atom)
                    let l:whole = 1
                    break
                endif
                call add(l:atoms, l:atom)
            endif
        endfor
        if l:whole
            continue
        endif
        let l:band = '\%>' . (l:first - 1) . 'l\%<' . (l:last + 1) . 'l'
        if empty(l:atoms)
            call add(l:pats, l:band . '.*')
        else
            call add(l:pats, l:band . join(map(uniq(sort(l:atoms)),
                \ '"\\%(" . v:val . "\\)\\@!"'), '') . '.')
        endif
    endfor
    return l:pats
endfunction

" ── Rendering ────────────────────────────────────────────────────────────────

function! s:clear_window(winid) abort
    for l:m in getmatches(a:winid)
        if l:m.group ==# 'SpotlightDim'
            call matchdelete(l:m.id, a:winid)
        endif
    endfor
endfunction

" Make the matches in one window reflect the buffer it currently shows.
function! s:render_window(winid) abort
    call s:clear_window(a:winid)
    let l:state = getbufvar(winbufnr(a:winid), 'spotlight', {})
    let l:pats = empty(l:state) ? [] : s:patterns(l:state)
    if empty(l:pats)
        call setwinvar(a:winid, 'spotlight', 0)
        return
    endif
    let l:prio = s:priority()
    for l:pat in l:pats
        call matchadd('SpotlightDim', l:pat, l:prio, -1, {'window': a:winid})
    endfor
    call setwinvar(a:winid, 'spotlight', 1)
endfunction

function! s:render_buffer(bufnr) abort
    for l:winid in win_findbuf(a:bufnr)
        call s:render_window(l:winid)
    endfor
    call s:update_suppression()
    call s:update_search_highlight()
endfunction

" True when the current buffer has a region lit right now.
function! s:is_lit() abort
    let l:state = get(b:, 'spotlight', {})
    return !empty(l:state) && !empty(s:lit_regions(l:state))
endfunction

" ── Optional cursor-event suppression ────────────────────────────────────────
"
" Off by default: it is global (it affects every plugin and matchparen), so
" it is opt-in via g:spotlight_suppress_cursor_events. Only the events this
" plugin added are ever removed again, so a user's own 'eventignore' edits are
" preserved.
"
" Word-under-cursor highlights are updated on CursorMoved, which is now
" ignored, so one drawn just before the spotlight went on would stay frozen.
" While suppressing, the plugin therefore hides them in the spotlighted
" windows: the :match highlight (what hand-rolled cursor-word scripts use),
" the built-in matchparen's :3match, coc.nvim's document highlight and
" vim-matchup's pair highlight. The :match is put back when the suppression
" ends, and CursorMoved is fired once so all of them recompute.
"
" coc.nvim requests its highlight on CursorHold and applies the answer
" whenever the language server replies (up to its documentHighlight.timeout,
" 5s at most), so a reply can land after the spotlight went on. For that long
" the spotlighted windows are swept again every 100ms.

function! s:hide_cursor_highlights() abort
    for l:winid in win_findbuf(bufnr('%'))
        for l:m in getmatches(l:winid)
            if l:m.id == 1 && !has_key(s:hidden_match, l:winid)
                let s:hidden_match[l:winid] = l:m
            endif
            if l:m.id == 1 || l:m.id == 3 || l:m.group =~# s:cursor_hl_groups
                silent! call matchdelete(l:m.id, l:winid)
            endif
        endfor
    endfor
endfunction

function! s:sweep_late_highlights() abort
    call s:stop_sweep()
    if exists('*timer_start')
        let s:sweep_timer = timer_start(s:sweep_interval,
            \ function('s:on_sweep'), {'repeat': s:sweep_count})
    endif
endfunction

function! s:stop_sweep() abort
    if s:sweep_timer != -1
        call timer_stop(s:sweep_timer)
        let s:sweep_timer = -1
    endif
endfunction

function! s:on_sweep(timer) abort
    if s:suppressing && s:is_lit()
        call s:hide_cursor_highlights()
    else
        call s:stop_sweep()
    endif
endfunction

function! s:restore_cursor_highlights() abort
    for [l:winid, l:m] in items(s:hidden_match)
        let l:matches = getmatches(l:winid)
        if win_id2win(l:winid) && empty(filter(copy(l:matches), 'v:val.id == 1'))
            call setmatches(l:matches + [l:m], l:winid)
        endif
    endfor
    let s:hidden_match = {}
    if exists('#CursorMoved')
        silent doautocmd <nomodeline> CursorMoved
    endif
endfunction

function! s:update_suppression() abort
    let l:want = get(g:, 'spotlight_suppress_cursor_events', 0) && s:is_lit()
    if l:want
        call s:hide_cursor_highlights()
    endif
    if l:want == s:suppressing
        return
    endif
    let s:suppressing = l:want
    let l:current = split(&eventignore, ',')
    if l:want
        let s:ei_added = filter(copy(s:cursor_events),
            \ 'index(l:current, v:val) < 0 && index(l:current, "all") < 0')
        let &eventignore = join(l:current + s:ei_added, ',')
        call s:sweep_late_highlights()
    else
        let &eventignore = join(filter(l:current,
            \ 'index(s:ei_added, v:val) < 0'), ',')
        let s:ei_added = []
        call s:stop_sweep()
        call s:restore_cursor_highlights()
    endif
endfunction

" ── Optional search-highlight hiding ─────────────────────────────────────────
"
" Off by default (g:spotlight_hide_search). 'hlsearch' is global and n/N turn
" the highlight back on after :nohlsearch, so the option itself is switched
" off while the current buffer has a spotlight. It is restored afterwards,
" unless the user turned it back on meanwhile.

function! s:update_search_highlight() abort
    let l:want = get(g:, 'spotlight_hide_search', 0) && s:is_lit()
    if l:want && !s:hls_hidden
        let s:hls_hidden = 1
        let s:hls_saved = &hlsearch
        set nohlsearch
    elseif !l:want && s:hls_hidden
        let s:hls_hidden = 0
        if !&hlsearch
            let &hlsearch = s:hls_saved
        endif
    endif
endfunction

" ── Regions ──────────────────────────────────────────────────────────────────

augroup spotlight_buffer
    autocmd!
augroup END

" Add a region to the current buffer, or with {replace} make it the only one.
function! s:activate(mode, pos, vcols, replace) abort
    let [l:sl, l:sc, l:el, l:ec] = a:pos
    if l:sl < 1 || l:el < l:sl
        return
    endif
    let l:bufnr = bufnr('%')
    if a:mode !=# 'char'
        " Line and block regions track whole lines.
        let l:sc = 1
        let l:ec = len(getline(l:el)) + 1
    endif

    if a:replace || !exists('b:spotlight')
        call s:anchor_clear(l:bufnr)
        let b:spotlight = {'regions': [], 'focus': 0, 'next_id': 1}
    endif
    let l:region = {
        \ 'id': b:spotlight.next_id,
        \ 'mode': a:mode,
        \ 'pos': [l:sl, l:sc, l:el, l:ec],
        \ 'vcols': a:vcols,
        \ 'enabled': 1,
        \ }
    let l:region.anchor = s:anchor_set(l:bufnr, l:region)
    let b:spotlight.next_id += 1
    let b:spotlight.lines = line('$')
    " A new region is meant to be seen: show everything again.
    let b:spotlight.focus = 0
    let b:spotlight.walk = []
    call add(b:spotlight.regions, l:region)

    execute 'autocmd! spotlight_buffer * <buffer=' . l:bufnr . '>'
    let l:events = 'TextChanged,TextChangedI'
        \ . (exists('##TextChangedP') ? ',TextChangedP' : '')
    execute 'autocmd spotlight_buffer ' . l:events . ' <buffer=' . l:bufnr
        \ . '> call spotlight#refresh(' . l:bufnr . ')'

    call s:render_buffer(l:bufnr)
endfunction

function! s:add_lines(line1, line2, replace) abort
    call s:activate('line', [a:line1, 1, a:line2, 1], [], a:replace)
endfunction

" {ec} is the inclusive byte column of the last character's first byte, the
" way '> and '] report it.
function! s:add_chars(sl, sc, el, ec, replace) abort
    let l:ecx = a:ec + max([1, s:char_len(a:el, a:ec)])
    let l:ecx = min([l:ecx, len(getline(a:el)) + 1])
    if a:sl == a:el && l:ecx <= a:sc
        return
    endif
    call s:activate('char', [a:sl, a:sc, a:el, l:ecx], [], a:replace)
endfunction

" A block from two corner positions (as returned by getpos()); {to_eol} is
" true when the block was extended with '$'.
function! s:add_block(p1, p2, to_eol, replace) abort
    let [l:l1, l:c1, l:o1] = a:p1[1:3]
    let [l:l2, l:c2, l:o2] = a:p2[1:3]
    let l:left = min([s:vcol_start(l:l1, l:c1, l:o1),
        \ s:vcol_start(l:l2, l:c2, l:o2)])
    let l:right = a:to_eol ? 0 : max([s:vcol_end(l:l1, l:c1, l:o1),
        \ s:vcol_end(l:l2, l:c2, l:o2)])
    call s:activate('block', [min([l:l1, l:l2]), 1, max([l:l1, l:l2]), 1],
        \ [l:left, l:right], a:replace)
endfunction

function! s:from_visual(to_eol, replace) abort
    let l:mode = visualmode()
    let l:p1 = getpos("'<")
    let l:p2 = getpos("'>")
    if l:mode ==# 'V'
        call s:add_lines(l:p1[1], l:p2[1], a:replace)
    elseif l:mode ==# "\<C-v>"
        call s:add_block(l:p1, l:p2, a:to_eol, a:replace)
    elseif &selection ==# 'exclusive'
        " '> is the first excluded character; step back to the last lit one.
        let l:ec = l:p2[2] - 1
        let l:el = l:p2[1]
        if l:ec < 1 && l:el > l:p1[1]
            let l:el -= 1
            let l:ec = max([1, len(getline(l:el))])
        endif
        call s:add_chars(l:p1[1], l:p1[2], l:el, max([1, l:ec]), a:replace)
    else
        call s:add_chars(l:p1[1], l:p1[2], l:p2[1], l:p2[2], a:replace)
    endif
endfunction

function! s:from_operator(type, replace) abort
    let l:p1 = getpos("'[")
    let l:p2 = getpos("']")
    if a:type ==# 'line'
        call s:add_lines(l:p1[1], l:p2[1], a:replace)
    elseif a:type ==# 'block'
        call s:add_block(l:p1, l:p2, 0, a:replace)
    else
        " Exact bounds so the delimiters of i{ / i( / it stay dimmed.
        call s:add_chars(l:p1[1], l:p1[2], l:p2[1], l:p2[2], a:replace)
    endif
endfunction

" True when the cursor position {pos} ([lnum, col]) is inside {region}.
function! s:contains(region, lnum, col) abort
    let [l:sl, l:sc, l:el, l:ec] = a:region.pos
    if a:lnum < l:sl || a:lnum > l:el
        return 0
    endif
    if a:region.mode ==# 'line'
        return 1
    endif
    if a:region.mode ==# 'block'
        let [l:left, l:right] = a:region.vcols
        let l:vcol = virtcol([a:lnum, a:col])
        return l:vcol >= l:left && (l:right == 0 || l:vcol <= l:right)
    endif
    return (a:lnum > l:sl || a:col >= l:sc) && (a:lnum < l:el || a:col < l:ec)
endfunction

" Number of lines a region spans, to pick the innermost of nested regions.
function! s:size(region) abort
    return (a:region.pos[2] - a:region.pos[0]) * 100000
        \ + (a:region.pos[3] - a:region.pos[1])
endfunction

" Regions in buffer order (by start line, then column).
function! s:by_position(a, b) abort
    let [l:a, l:b] = [a:a.pos, a:b.pos]
    return l:a[0] != l:b[0] ? l:a[0] - l:b[0] : l:a[1] - l:b[1]
endfunction

function! s:message(text) abort
    echohl WarningMsg
    echo 'spotlight: ' . a:text
    echohl None
endfunction

" ── Public API ───────────────────────────────────────────────────────────────

" True when the current buffer has any spotlight region (lit or switched off).
function! spotlight#is_active() abort
    return !empty(get(get(b:, 'spotlight', {}), 'regions', []))
endfunction

" Spotlight lines {line1}..{line2}, replacing any other region.
function! spotlight#lines(line1, line2) abort
    call s:add_lines(a:line1, a:line2, 1)
endfunction

" Add lines {line1}..{line2} as another region.
function! spotlight#add_lines(line1, line2) abort
    call s:add_lines(a:line1, a:line2, 0)
endfunction

" Kept for compatibility: a character-wise or block region, replacing others.
function! spotlight#chars(sl, sc, el, ec) abort
    call s:add_chars(a:sl, a:sc, a:el, a:ec, 1)
endfunction

function! spotlight#block(p1, p2, to_eol) abort
    call s:add_block(a:p1, a:p2, a:to_eol, 1)
endfunction

" Called (through a mapping) right after leaving Visual mode.
function! spotlight#visual(to_eol, ...) abort
    call s:from_visual(a:to_eol, a:0 ? !a:1 : 1)
endfunction

" <expr> helpers for the Visual-mode mappings. They run while Visual mode is
" still active, which is the only time a trailing '$' (curswant == MAXCOL)
" can be detected.
function! spotlight#visual_map(...) abort
    let l:to_eol = getcurpos()[4] >= s:maxcol ? 1 : 0
    let l:add = a:0 ? a:1 : 0
    return ":\<C-u>call spotlight#visual(" . l:to_eol . ', ' . l:add . ")\<CR>"
endfunction

function! spotlight#visual_toggle_map() abort
    if spotlight#is_active()
        return "\<Esc>:\<C-u>call spotlight#clear()\<CR>"
    endif
    return spotlight#visual_map()
endfunction

" 'operatorfunc' targets: replace, or add a region.
function! spotlight#operator(type) abort
    call s:from_operator(a:type, 1)
endfunction

function! spotlight#add_operator(type) abort
    call s:from_operator(a:type, 0)
endfunction

" Normal-mode entry point: clear when a spotlight is active, otherwise start
" the operator. Avoids the double-press footgun where a second <leader>h would
" be read as a motion in Operator-pending mode.
function! spotlight#operator_map() abort
    if spotlight#is_active()
        return ":\<C-u>call spotlight#clear()\<CR>"
    endif
    let &operatorfunc = 'spotlight#operator'
    return 'g@'
endfunction

function! spotlight#add_operator_map() abort
    let &operatorfunc = 'spotlight#add_operator'
    return 'g@'
endfunction

" :[range]Spotlight[!]
function! spotlight#command(bang, line1, line2) abort
    if a:bang
        call spotlight#clear()
    else
        call spotlight#lines(a:line1, a:line2)
    endif
endfunction

" Switch the region under the cursor off (kept, but dimmed) or back on. With
" nested regions the innermost one is switched. Also leaves focus mode.
function! spotlight#toggle_region() abort
    let l:state = get(b:, 'spotlight', {})
    let l:here = filter(copy(get(l:state, 'regions', [])),
        \ 's:contains(v:val, line("."), col("."))')
    if empty(l:here)
        call s:message('no region under the cursor')
        return
    endif
    let l:region = sort(l:here, {a, b -> s:size(a) - s:size(b)})[0]
    let l:region.enabled = !l:region.enabled
    let l:state.focus = 0
    let l:state.walk = []
    call s:render_buffer(bufnr('%'))
endfunction

" Light only the next ({step} = 1) or previous ({step} = -1) enabled region,
" moving the cursor to it. Stepping past the last (or first) region lights
" all of them again.
function! spotlight#focus(step) abort
    let l:state = get(b:, 'spotlight', {})
    " In follow mode, walk the blocks inside the block it has lit.
    if has_key(s:follow, bufnr('%'))
        \ && index(get(l:state, 'walk', []), get(l:state, 'focus', 0)) < 0
        let l:outer = s:block_around(line('.'))
        if empty(l:outer)
            call s:message('no indented block around the cursor')
            return
        endif
        call s:start_walk(l:outer)
        let l:state = b:spotlight
    endif
    " After <leader>hd: walk the blocks inside the outer one, wrapping round
    " to the whole outer block.
    let l:walk = get(l:state, 'walk', [])
    if index(l:walk, get(l:state, 'focus', 0)) >= 0
        let l:at = (index(l:walk, l:state.focus) + a:step + len(l:walk))
            \ % len(l:walk)
        let l:state.focus = l:walk[l:at]
        let l:region = filter(copy(l:state.regions),
            \ 'v:val.id == l:state.focus')[0]
        normal! m'
        call cursor(l:region.pos[0], 1)
        normal! ^
        call s:render_buffer(bufnr('%'))
        call s:follow_sync()
        return
    endif
    let l:regions = sort(filter(copy(get(l:state, 'regions', [])),
        \ 'v:val.enabled'), function('s:by_position'))
    if empty(l:regions)
        call s:message('no regions to focus')
        return
    endif
    let l:ids = map(copy(l:regions), 'v:val.id')
    " Position -1 stands for "all regions", before the first and after the last.
    let l:at = index(l:ids, l:state.focus)
    let l:next = l:at + a:step
    if l:at == -1 && a:step < 0
        let l:next = len(l:ids) - 1
    endif
    if l:next < 0 || l:next >= len(l:ids)
        let l:state.focus = 0
    else
        let l:state.focus = l:ids[l:next]
        normal! m'
        call cursor(l:regions[l:next].pos[0], l:regions[l:next].pos[1])
    endif
    call s:render_buffer(bufnr('%'))
endfunction

" ── Blocks ───────────────────────────────────────────────────────────────────
"
" <leader>hd lights the innermost block of code around the cursor, found by
" indentation: a line followed by more-indented lines starts a block, which
" runs until the indentation comes back (blank lines don't end it), plus a
" closing line at the same indentation (}, ), ], </tag>, />, end, ...).
" Inside a block, runs of lines separated by blank lines (chunks) count as
" blocks too. Every block and chunk inside the lit one becomes a region as
" well, and <leader>hn / hb walk through those, coming back to the whole
" block after the last one.

let s:closer = '^\s*\%([\])}]\|</\|/\=>\|end\>\|fi\>\|done\>\|esac\>\)'

function! s:blank(lnum) abort
    return getline(a:lnum) =~# '^\s*$'
endfunction

" The block whose header is {head}: [head, last line], or [] when the next
" non-blank line is not indented deeper.
function! s:block_at(head) abort
    let l:ind = indent(a:head)
    let l:next = nextnonblank(a:head + 1)
    if !l:next || indent(l:next) <= l:ind
        return []
    endif
    let l:last = l:next
    let l:lnum = l:next + 1
    while l:lnum <= line('$') && (s:blank(l:lnum) || indent(l:lnum) > l:ind)
        if !s:blank(l:lnum)
            let l:last = l:lnum
        endif
        let l:lnum += 1
    endwhile
    let l:after = nextnonblank(l:last + 1)
    if l:after && indent(l:after) == l:ind && getline(l:after) =~# s:closer
        let l:last = l:after
    endif
    return [a:head, l:last]
endfunction

" Header of the block that directly contains line {lnum}: the nearest line
" above it with less indentation, or 0.
function! s:parent_head(lnum) abort
    let l:ind = indent(a:lnum)
    let l:lnum = prevnonblank(a:lnum - 1)
    while l:lnum > 0 && indent(l:lnum) >= l:ind
        let l:lnum = prevnonblank(l:lnum - 1)
    endwhile
    return l:lnum
endfunction

" Lines [first, last] of {block}'s body: after its header, without its own
" closing line.
function! s:body(block) abort
    let [l:head, l:last] = a:block
    if l:last > l:head && indent(l:last) == indent(l:head)
        \ && getline(l:last) =~# s:closer
        let l:last = prevnonblank(l:last - 1)
    endif
    return [l:head + 1, l:last]
endfunction

" Chunks of the body [first, last]: runs of lines split by blank lines at the
" body's own indentation. A blank line inside a deeper block (followed by a
" more indented line) does not split.
function! s:chunks(first, last) abort
    let l:lnum = nextnonblank(a:first)
    if !l:lnum || l:lnum > a:last
        return []
    endif
    let l:base = indent(l:lnum)
    let l:chunks = []
    while l:lnum && l:lnum <= a:last
        let l:end = l:lnum
        let l:next = l:lnum + 1
        while l:next <= a:last
            if s:blank(l:next)
                let l:after = nextnonblank(l:next)
                if !l:after || l:after > a:last || indent(l:after) <= l:base
                    break
                endif
                let l:next = l:after
                continue
            endif
            let l:end = l:next
            let l:next += 1
        endwhile
        call add(l:chunks, [l:lnum, l:end])
        let l:lnum = nextnonblank(l:end + 1)
    endwhile
    return l:chunks
endfunction

" The innermost block around {lnum}: on a header line, its block; otherwise
" the chunk of lines it is in (when the enclosing body has more than one),
" or else the enclosing block. [] when there is none.
function! s:block_around(lnum) abort
    let l:lnum = s:blank(a:lnum) ? prevnonblank(a:lnum) : a:lnum
    if !l:lnum
        return []
    endif
    " On a closing line (}), belong to the block it closes.
    if getline(l:lnum) =~# s:closer
        let l:open = prevnonblank(l:lnum - 1)
        while l:open > 0 && indent(l:open) > indent(l:lnum)
            let l:open = prevnonblank(l:open - 1)
        endwhile
        if l:open > 0 && indent(l:open) == indent(l:lnum)
            return s:block_at(l:open)
        endif
    endif
    let l:own = s:block_at(l:lnum)
    if !empty(l:own)
        return l:own
    endif
    let l:parent = []
    let l:head = s:parent_head(l:lnum)
    while l:head > 0
        let l:block = s:block_at(l:head)
        if !empty(l:block) && l:block[1] >= l:lnum
            let l:parent = l:block
            break
        endif
        let l:head = s:parent_head(l:head)
    endwhile
    let l:range = empty(l:parent) ? [1, line('$')] : s:body(l:parent)
    let l:chunks = s:chunks(l:range[0], l:range[1])
    if len(l:chunks) > 1
        for l:chunk in l:chunks
            if l:chunk[0] <= l:lnum && l:lnum <= l:chunk[1]
                return l:chunk
            endif
        endfor
    endif
    return l:parent
endfunction

" The innermost indented block that strictly contains {block}, or [].
function! s:enclosing_block(block) abort
    let l:head = s:parent_head(a:block[0])
    while l:head > 0
        let l:candidate = s:block_at(l:head)
        if !empty(l:candidate) && l:candidate[1] >= a:block[1]
            \ && l:candidate != a:block
            return l:candidate
        endif
        let l:head = s:parent_head(l:head)
    endwhile
    return []
endfunction

" What <leader>hn walks inside the lines [first, last], in file order: each
" chunk (when there is more than one), then each block whose header is at
" the chunk's indentation, followed by what is inside that block.
function! s:walk_items(first, last) abort
    let l:chunks = s:chunks(a:first, a:last)
    let l:items = []
    for l:chunk in l:chunks
        if len(l:chunks) > 1
            call add(l:items, l:chunk)
        endif
        let l:base = indent(l:chunk[0])
        for l:lnum in range(l:chunk[0], l:chunk[1])
            if s:blank(l:lnum) || indent(l:lnum) != l:base
                continue
            endif
            let l:block = s:block_at(l:lnum)
            if !empty(l:block) && l:block[1] <= l:chunk[1]
                call add(l:items, l:block)
                call extend(l:items, call('s:walk_items', s:body(l:block)))
            endif
        endfor
    endfor
    return l:items
endfunction

" {outer} followed by everything to walk inside it, without repeats.
function! s:walk_list(outer) abort
    let l:inner = a:outer == s:block_at(a:outer[0])
        \ ? s:body(a:outer) : a:outer
    let l:seen = {}
    let l:list = []
    for l:item in [a:outer] + s:walk_items(l:inner[0], l:inner[1])
        let l:key = l:item[0] . '-' . l:item[1]
        if !has_key(l:seen, l:key)
            let l:seen[l:key] = 1
            call add(l:list, l:item)
        endif
    endfor
    return l:list
endfunction

function! spotlight#blocks() abort
    let l:outer = s:block_around(line('.'))
    if empty(l:outer)
        call s:message('no indented block around the cursor')
        return
    endif
    call s:start_walk(l:outer)
    call s:follow_sync()
endfunction

" Light {outer} and make it and every block inside it the regions walked by
" <leader>hn / hb.
function! s:start_walk(outer) abort
    let l:list = s:walk_list(a:outer)
    let l:start = 0
    if len(l:list) == 1
        " Nothing inside: walk its neighbours in the enclosing block (or the
        " top level), starting from it.
        let l:parent = s:enclosing_block(a:outer)
        let l:list = empty(l:parent) ? s:walk_items(1, line('$'))
            \ : s:walk_list(l:parent)
        let l:start = max([0, index(l:list, a:outer)])
        if empty(l:list)
            let l:list = [a:outer]
        endif
    endif
    let l:replace = 1
    for [l:first, l:last] in l:list
        call s:activate('line', [l:first, 1, l:last, 1], [], l:replace)
        let l:replace = 0
        " An indented block re-measures where it ends as you edit.
        if s:block_at(l:first) == [l:first, l:last]
            let b:spotlight.regions[-1].block_indent = indent(l:first)
        endif
    endfor
    " Regions were added in walking order.
    let b:spotlight.walk = map(copy(b:spotlight.regions), 'v:val.id')
    let b:spotlight.focus = b:spotlight.walk[l:start]
    call s:render_buffer(bufnr('%'))
endfunction

" ── Follow mode ──────────────────────────────────────────────────────────────
"
" <leader>hm: while on, the block around the cursor is lit automatically as
" the cursor moves. A timer checks the cursor line (rather than CursorMoved),
" so it keeps working while g:spotlight_suppress_cursor_events ignores cursor
" events. Work is only done when the line or the text changed.

" Buffers following the cursor, by number.
let s:follow = {}
let s:follow_timer = -1

function! spotlight#follow_toggle() abort
    if has_key(s:follow, bufnr('%'))
        call spotlight#clear()
        echo 'spotlight: stopped following the cursor'
    else
        call spotlight#follow_start()
    endif
endfunction

function! spotlight#follow_start() abort
    if !exists('*timer_start')
        call s:message('following the cursor needs +timers')
        return
    endif
    let s:follow[bufnr('%')] = 1
    let b:spotlight_follow_key = ''
    call s:follow_update()
    if s:follow_timer == -1
        let s:follow_timer = timer_start(100, function('s:on_follow'),
            \ {'repeat': -1})
    endif
    echo 'spotlight: following the cursor'
endfunction

" The cursor was moved by the plugin itself (walking blocks): follow mode
" must not treat that as the user moving to another block.
function! s:follow_sync() abort
    if has_key(s:follow, bufnr('%'))
        let b:spotlight_follow_key = line('.') . ':' . b:changedtick
    endif
endfunction

function! s:follow_stop(bufnr) abort
    if has_key(s:follow, a:bufnr)
        call remove(s:follow, a:bufnr)
    endif
    call setbufvar(a:bufnr, 'spotlight_follow_key', '')
    if empty(s:follow) && s:follow_timer != -1
        call timer_stop(s:follow_timer)
        let s:follow_timer = -1
    endif
endfunction

function! s:on_follow(timer) abort
    for l:bufnr in keys(s:follow)
        if !bufexists(str2nr(l:bufnr))
            call s:follow_stop(str2nr(l:bufnr))
        endif
    endfor
    if has_key(s:follow, bufnr('%')) && mode() !=# 'c'
        call s:follow_update()
    endif
endfunction

function! s:follow_update() abort
    let l:key = line('.') . ':' . b:changedtick
    if l:key ==# get(b:, 'spotlight_follow_key', '')
        return
    endif
    let b:spotlight_follow_key = l:key
    let l:block = s:block_around(line('.'))
    let l:regions = get(get(b:, 'spotlight', {}), 'regions', [])
    if empty(l:block)
        " Top level: nothing to light, but keep following.
        if !empty(l:regions)
            call s:clear_regions(bufnr('%'))
        endif
        return
    endif
    if len(l:regions) == 1 && l:regions[0].pos[0] == l:block[0]
        \ && l:regions[0].pos[2] == l:block[1]
        return
    endif
    call s:activate('line', [l:block[0], 1, l:block[1], 1], [], 1)
endfunction

function! s:clear_regions(bufnr) abort
    call s:anchor_clear(a:bufnr)
    silent! unlet b:spotlight
    execute 'autocmd! spotlight_buffer * <buffer=' . a:bufnr . '>'
    call s:render_buffer(a:bufnr)
endfunction

" Clear every region in the current buffer and stop following the cursor.
function! spotlight#clear() abort
    call s:follow_stop(bufnr('%'))
    call s:clear_regions(bufnr('%'))
endfunction

" Re-read the anchors after an edit and redraw every window on {bufnr}.
"
" A region whose anchor is gone while others still have theirs had all of its
" text deleted, so it is dropped. When every anchor is gone at once the
" buffer was reloaded or replaced (:edit!, :%!fmt): the regions keep their
" old coordinates, clamped to the buffer, and are anchored again.
function! spotlight#refresh(...) abort
    let l:bufnr = a:0 ? a:1 : bufnr('%')
    let l:state = getbufvar(l:bufnr, 'spotlight', {})
    if empty(l:state)
        return
    endif
    let l:last = s:line_count(l:bufnr)
    let l:delta = l:last - get(l:state, 'lines', l:last)
    let l:found = map(copy(l:state.regions),
        \ 's:anchor_get(l:bufnr, v:val, l:delta)')
    let l:reloaded = empty(filter(copy(l:found), '!empty(v:val)'))

    let l:kept = []
    for l:i in range(len(l:state.regions))
        let l:region = l:state.regions[l:i]
        let l:pos = l:found[l:i]
        if empty(l:pos) && !l:reloaded
            call s:anchor_del(l:bufnr, l:region)
            if l:state.focus == l:region.id
                let l:state.focus = 0
            endif
            continue
        endif
        if empty(l:pos)
            let [l:sl, l:sc, l:el, l:ec] = l:region.pos
            let l:el = min([max([l:el, 1]), l:last])
            let l:sl = min([max([l:sl, 1]), l:el])
            let l:pos = [l:sl, l:sc, l:el, l:ec]
            if get(l:region, 'anchor', 0) && bufnr('%') == l:bufnr
                call s:anchor_del(l:bufnr, l:region)
                let l:region.pos = l:pos
                let l:region.anchor = s:anchor_set(l:bufnr, l:region)
            endif
        endif
        let l:region.pos = l:pos
        if has_key(l:region, 'block_indent') && bufnr('%') == l:bufnr
            call s:remeasure_block(l:bufnr, l:region)
        endif
        call add(l:kept, l:region)
    endfor
    let l:state.regions = l:kept
    let l:state.lines = l:last
    call s:render_buffer(l:bufnr)
endfunction

" A region made by <leader>hd: while its first line is still the block's
" header (same indentation), take its end from the indentation again, so a
" line added after the last one (no closing brace in Python) is included.
function! s:remeasure_block(bufnr, region) abort
    let l:first = a:region.pos[0]
    if indent(l:first) != a:region.block_indent
        return
    endif
    let l:block = s:block_at(l:first)
    if empty(l:block) || l:block[1] == a:region.pos[2]
        return
    endif
    let a:region.pos = [l:first, 1, l:block[1], len(getline(l:block[1])) + 1]
    call s:anchor_del(a:bufnr, a:region)
    let a:region.anchor = s:anchor_set(a:bufnr, a:region)
endfunction

" BufWinEnter / WinEnter: bring the current window in line with its buffer
" (drop matches left over from another buffer, pick up this buffer's).
function! spotlight#sync_window() abort
    if spotlight#is_active()
        call spotlight#refresh()
    else
        call s:render_window(win_getid())
        call s:update_suppression()
        call s:update_search_highlight()
    endif
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
