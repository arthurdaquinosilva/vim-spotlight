scriptencoding utf-8
" autoload/spotlight.vim — core logic for vim-spotlight
" Source: https://github.com/arthurdaquinosilva/vim-spotlight
" License: MIT

let s:save_cpo = &cpoptions
set cpoptions&vim

" ── Model ────────────────────────────────────────────────────────────────────
"
" A spotlight lives in b:spotlight, so it is per-buffer and disappears with
" the buffer. Shape:
"
"   mode   'char' | 'line' | 'block'
"   pos    [sl, sc, el, ec]  1-based lines and byte columns; ec is exclusive
"                            (one past the last lit byte). Columns are ignored
"                            in 'line' mode.
"   vcols  [left, right]     'block' mode only: inclusive screen columns.
"                            right == 0 means "to the end of every line".
"   lines  buffer line count when pos was last updated
"   anchor id of the text property / extmark that tracks pos across edits
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
" Match groups of cursor-word highlights (coc.nvim's document highlight).
let s:cursor_hl_groups = '^CocHighlight'

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

" ── Position anchors (track the region while the buffer is edited) ───────────
"
" Vim: one multi-line text property spanning the region. Text properties move
" with inserted/deleted text, survive deletion of the first or last line
" (the remaining segments simply become the new edge) and are restored by
" undo. Neovim: one extmark with an end position. Without either, the region
" stays at fixed coordinates.

function! s:anchor_set(bufnr, mode, pos) abort
    call s:anchor_del(a:bufnr)
    let [l:sl, l:sc, l:el, l:ec] = a:pos
    if s:has_nvim
        " Gravity mirrors Vim's start_incl/end_incl: typing at either edge of a
        " char-wise region extends it, while for line/block regions a line
        " opened right above the first line stays outside.
        let l:opts = {
            \ 'end_col': l:ec - 1,
            \ 'right_gravity': a:mode ==# 'char' ? v:false : v:true,
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
            \ 'bufnr': a:bufnr,
            \ 'end_lnum': l:el,
            \ 'end_col': l:ec,
            \ })
        return 1
    endif
    return 0
endfunction

function! s:anchor_del(bufnr) abort
    if s:has_nvim
        call nvim_buf_clear_namespace(a:bufnr, s:ns, 0, -1)
    elseif s:has_textprop && !empty(prop_type_get(s:prop_type))
        call prop_remove({'type': s:prop_type, 'bufnr': a:bufnr, 'all': 1},
            \ 1, s:line_count(a:bufnr))
    endif
endfunction

" Returns the anchored [sl, sc, el, ec], or [] when the anchor is gone (for
" example after :edit! reloaded the file).
function! s:anchor_get(bufnr, state) abort
    if !get(a:state, 'anchor', 0)
        return []
    endif
    if s:has_nvim
        let l:m = nvim_buf_get_extmark_by_id(a:bufnr, s:ns, a:state.anchor,
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
    let [l:osl, l:oel] = [a:state.pos[0], a:state.pos[2]]
    let l:delta = s:line_count(a:bufnr) - get(a:state, 'lines', 0)

    let l:first = s:segment_at(a:bufnr, [l:osl, l:osl + l:delta], 'start')
    if empty(l:first)
        let l:first = s:find_start(a:bufnr)
        if empty(l:first)
            return []
        endif
    endif
    let l:sl = l:first.lnum
    let l:sc = l:first.start ? l:first.col : 1

    let l:last = s:segment_at(a:bufnr,
        \ filter([l:oel, l:oel + l:delta], 'v:val >= l:sl'), 'end')
    if empty(l:last)
        let l:last = s:scan_to_end(a:bufnr, l:sl)
        if empty(l:last)
            return []
        endif
    endif
    let l:ec = l:last.col + l:last.length - (l:last.end ? 0 : 1)
    return [l:sl, l:sc, l:last.lnum, l:ec]
endfunction

" Our property's segment on the first of {lnums} where it carries {flag}
" ('start' or 'end'), with 'lnum' added; {} when there is none.
function! s:segment_at(bufnr, lnums, flag) abort
    let l:total = s:line_count(a:bufnr)
    for l:lnum in a:lnums
        if l:lnum < 1 || l:lnum > l:total
            continue
        endif
        for l:seg in prop_list(l:lnum, {'bufnr': a:bufnr})
            if get(l:seg, 'type', '') ==# s:prop_type && l:seg[a:flag]
                return extend(l:seg, {'lnum': l:lnum})
            endif
        endfor
    endfor
    return {}
endfunction

" Slow path: the first segment of our property in the buffer.
function! s:find_start(bufnr) abort
    if s:has_prop_find
        return prop_find({'type': s:prop_type, 'bufnr': a:bufnr,
            \ 'lnum': 1, 'col': 1}, 'f')
    endif
    for l:lnum in range(1, s:line_count(a:bufnr))
        for l:seg in prop_list(l:lnum, {'bufnr': a:bufnr})
            if get(l:seg, 'type', '') ==# s:prop_type
                return extend(l:seg, {'lnum': l:lnum})
            endif
        endfor
    endfor
    return {}
endfunction

" Slow path: walk from {from} to the segment that ends the property.
function! s:scan_to_end(bufnr, from) abort
    if s:has_prop_range
        let l:segs = prop_list(a:from, {'bufnr': a:bufnr, 'end_lnum': -1,
            \ 'types': [s:prop_type]})
        return empty(l:segs) ? {} : l:segs[-1]
    endif
    let l:last = {}
    let l:total = s:line_count(a:bufnr)
    let l:lnum = a:from
    while l:lnum <= l:total
        let l:segs = filter(prop_list(l:lnum, {'bufnr': a:bufnr}),
            \ 'get(v:val, "type", "") ==# s:prop_type')
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

function! s:patterns(state) abort
    let [l:sl, l:sc, l:el, l:ec] = a:state.pos
    let l:pats = []

    if l:sl > 1
        call add(l:pats, '\%<' . l:sl . 'l.*')
    endif
    " Added even on the last line: if lines are appended from another window
    " or by a plugin, they are dimmed before the next refresh runs.
    call add(l:pats, '\%>' . l:el . 'l.*')

    if a:state.mode ==# 'block'
        " Dim the screen columns outside [left, right] on every line in the
        " band; \%v is used (not \%c) so tabs and wide characters line up.
        let [l:left, l:right] = a:state.vcols
        let l:band = '\%>' . (l:sl - 1) . 'l\%<' . (l:el + 1) . 'l'
        if l:left > 1
            call add(l:pats, l:band . '\%<' . l:left . 'v.')
        endif
        if l:right > 0
            call add(l:pats, l:band . '\%>' . l:right . 'v.')
        endif
    elseif a:state.mode ==# 'char'
        if l:sc > 1
            call add(l:pats, '\%' . l:sl . 'l\%<' . l:sc . 'c.')
        endif
        call add(l:pats, '\%' . l:el . 'l\%>' . (l:ec - 1) . 'c.')
    endif
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
    if empty(l:state)
        call setwinvar(a:winid, 'spotlight', 0)
        return
    endif
    let l:prio = s:priority()
    for l:pat in s:patterns(l:state)
        call matchadd('SpotlightDim', l:pat, l:prio, -1, {'window': a:winid})
    endfor
    call setwinvar(a:winid, 'spotlight', 1)
endfunction

function! s:render_buffer(bufnr) abort
    for l:winid in win_findbuf(a:bufnr)
        call s:render_window(l:winid)
    endfor
    call s:update_suppression()
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
" windows: the :match highlight (what hand-rolled cursor-word scripts use)
" and coc.nvim's document highlight. The :match is put back when the
" suppression ends, and CursorMoved is fired once so such scripts recompute.

function! s:hide_cursor_highlights() abort
    for l:winid in win_findbuf(bufnr('%'))
        for l:m in getmatches(l:winid)
            if l:m.id == 1 && !has_key(s:hidden_match, l:winid)
                let s:hidden_match[l:winid] = l:m
            endif
            if l:m.id == 1 || l:m.group =~# s:cursor_hl_groups
                silent! call matchdelete(l:m.id, l:winid)
            endif
        endfor
    endfor
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
    let l:want = get(g:, 'spotlight_suppress_cursor_events', 0)
        \ && !empty(get(b:, 'spotlight', {}))
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
    else
        let &eventignore = join(filter(l:current,
            \ 'index(s:ei_added, v:val) < 0'), ',')
        let s:ei_added = []
        call s:restore_cursor_highlights()
    endif
endfunction

" ── Activation ───────────────────────────────────────────────────────────────

function! s:activate(mode, pos, vcols) abort
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
    let l:pos = [l:sl, l:sc, l:el, l:ec]

    let b:spotlight = {
        \ 'mode': a:mode,
        \ 'pos': l:pos,
        \ 'vcols': a:vcols,
        \ 'lines': line('$'),
        \ 'anchor': s:anchor_set(l:bufnr, a:mode, l:pos),
        \ }

    execute 'autocmd! spotlight_buffer * <buffer=' . l:bufnr . '>'
    let l:events = 'TextChanged,TextChangedI'
        \ . (exists('##TextChangedP') ? ',TextChangedP' : '')
    execute 'autocmd spotlight_buffer ' . l:events . ' <buffer=' . l:bufnr
        \ . '> call spotlight#refresh(' . l:bufnr . ')'

    call s:render_buffer(l:bufnr)
endfunction

augroup spotlight_buffer
    autocmd!
augroup END

" ── Public API ───────────────────────────────────────────────────────────────

function! spotlight#is_active() abort
    return !empty(get(b:, 'spotlight', {}))
endfunction

" Spotlight lines {line1}..{line2}.
function! spotlight#lines(line1, line2) abort
    call s:activate('line', [a:line1, 1, a:line2, 1], [])
endfunction

" Spotlight a character-wise region; {ec} is the inclusive byte column of the
" last character's first byte, the way '> and '] report it.
function! spotlight#chars(sl, sc, el, ec) abort
    let l:ecx = a:ec + max([1, s:char_len(a:el, a:ec)])
    let l:ecx = min([l:ecx, len(getline(a:el)) + 1])
    if a:sl == a:el && l:ecx <= a:sc
        return
    endif
    call s:activate('char', [a:sl, a:sc, a:el, l:ecx], [])
endfunction

" Spotlight a block from two corner positions (as returned by getpos()).
" {to_eol} is true when the block was extended with '$'.
function! spotlight#block(p1, p2, to_eol) abort
    let [l:l1, l:c1, l:o1] = a:p1[1:3]
    let [l:l2, l:c2, l:o2] = a:p2[1:3]
    let l:left = min([s:vcol_start(l:l1, l:c1, l:o1),
        \ s:vcol_start(l:l2, l:c2, l:o2)])
    let l:right = a:to_eol ? 0 : max([s:vcol_end(l:l1, l:c1, l:o1),
        \ s:vcol_end(l:l2, l:c2, l:o2)])
    call s:activate('block', [min([l:l1, l:l2]), 1, max([l:l1, l:l2]), 1],
        \ [l:left, l:right])
endfunction

" Called (through a mapping) right after leaving Visual mode.
function! spotlight#visual(to_eol) abort
    let l:mode = visualmode()
    let l:p1 = getpos("'<")
    let l:p2 = getpos("'>")
    if l:mode ==# 'V'
        call spotlight#lines(l:p1[1], l:p2[1])
    elseif l:mode ==# "\<C-v>"
        call spotlight#block(l:p1, l:p2, a:to_eol)
    elseif &selection ==# 'exclusive'
        " '> is the first excluded character; step back to the last lit one.
        let l:ec = l:p2[2] - 1
        let l:el = l:p2[1]
        if l:ec < 1 && l:el > l:p1[1]
            let l:el -= 1
            let l:ec = max([1, len(getline(l:el))])
        endif
        call spotlight#chars(l:p1[1], l:p1[2], l:el, max([1, l:ec]))
    else
        call spotlight#chars(l:p1[1], l:p1[2], l:p2[1], l:p2[2])
    endif
endfunction

" <expr> helpers for the Visual-mode mappings. They run while Visual mode is
" still active, which is the only time a trailing '$' (curswant == MAXCOL)
" can be detected.
function! spotlight#visual_map() abort
    let l:to_eol = getcurpos()[4] >= s:maxcol ? 1 : 0
    return ":\<C-u>call spotlight#visual(" . l:to_eol . ")\<CR>"
endfunction

function! spotlight#visual_toggle_map() abort
    if spotlight#is_active()
        return "\<Esc>:\<C-u>call spotlight#clear()\<CR>"
    endif
    return spotlight#visual_map()
endfunction

" 'operatorfunc' target.
function! spotlight#operator(type) abort
    let l:p1 = getpos("'[")
    let l:p2 = getpos("']")
    if a:type ==# 'line'
        call spotlight#lines(l:p1[1], l:p2[1])
    elseif a:type ==# 'block'
        call spotlight#block(l:p1, l:p2, 0)
    else
        " Exact bounds so the delimiters of i{ / i( / it stay dimmed.
        call spotlight#chars(l:p1[1], l:p1[2], l:p2[1], l:p2[2])
    endif
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

" :[range]Spotlight[!]
function! spotlight#command(bang, line1, line2) abort
    if a:bang
        call spotlight#clear()
    else
        call spotlight#lines(a:line1, a:line2)
    endif
endfunction

function! spotlight#clear() abort
    let l:bufnr = bufnr('%')
    call s:anchor_del(l:bufnr)
    silent! unlet b:spotlight
    execute 'autocmd! spotlight_buffer * <buffer=' . l:bufnr . '>'
    call s:render_buffer(l:bufnr)
endfunction

" Re-read the anchor after an edit and redraw every window on {bufnr}.
function! spotlight#refresh(...) abort
    let l:bufnr = a:0 ? a:1 : bufnr('%')
    let l:state = getbufvar(l:bufnr, 'spotlight', {})
    if empty(l:state)
        return
    endif
    let l:pos = s:anchor_get(l:bufnr, l:state)
    let l:last = s:line_count(l:bufnr)
    if empty(l:pos)
        " Anchor lost (e.g. :edit!): keep the old coordinates, clamped to the
        " buffer, and re-anchor them.
        let [l:sl, l:sc, l:el, l:ec] = l:state.pos
        let l:el = min([max([l:el, 1]), l:last])
        let l:sl = min([max([l:sl, 1]), l:el])
        let l:pos = [l:sl, l:sc, l:el, l:ec]
        if get(l:state, 'anchor', 0) && bufnr('%') == l:bufnr
            let l:state.anchor = s:anchor_set(l:bufnr, l:state.mode, l:pos)
        endif
    endif
    let l:state.pos = l:pos
    let l:state.lines = l:last
    call s:render_buffer(l:bufnr)
endfunction

" BufWinEnter / WinEnter: bring the current window in line with its buffer
" (drop matches left over from another buffer, pick up this buffer's).
function! spotlight#sync_window() abort
    if spotlight#is_active()
        call spotlight#refresh()
    else
        call s:render_window(win_getid())
        call s:update_suppression()
    endif
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
