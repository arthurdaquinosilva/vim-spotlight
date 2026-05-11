" autoload/spotlight.vim — core logic for vim-spotlight
" Source: https://github.com/arthurdaquinosilva/vim-spotlight
" License: MIT

let s:coc_disabled = 0
let s:saved_eventignore = ''
let s:buffer_states = {}

" ── Buffer state ──────────────────────────────────────────────────────────────

function! s:get_state() abort
    let l:bufnr = bufnr('%')
    if !has_key(s:buffer_states, l:bufnr)
        let s:buffer_states[l:bufnr] = {
            \ 'active': 0,
            \ 'selection': [],
            \ 'blockwise': 0
            \ }
    endif
    return s:buffer_states[l:bufnr]
endfunction

function! s:set_state(state) abort
    let s:buffer_states[bufnr('%')] = a:state
endfunction

function! s:clear_state() abort
    silent! unlet s:buffer_states[bufnr('%')]
endfunction

" ── Match management ─────────────────────────────────────────────────────────

function! s:clear_window_matches() abort
    for l:m in getmatches()
        if l:m.group ==# 'SpotlightDim'
            call matchdelete(l:m.id)
        endif
    endfor
endfunction

function! s:add_pattern(pattern) abort
    call matchadd('SpotlightDim', a:pattern, 100)
endfunction

function! s:apply_patterns(sl, sc, el, ec, block) abort
    let l:total = line('$')

    if a:sl > 1
        call s:add_pattern('\%<' . a:sl . 'l.*')
    endif
    if a:el < l:total
        call s:add_pattern('\%>' . a:el . 'l.*')
    endif

    if a:block
        " Block-wise (<C-v>): dim the columns outside [sc, ec] on *every* line
        " in the range, leaving a rectangular column of text lit. The line
        " bounds \%>{sl-1}l ... \%<{el+1}l confine the column dimming to the
        " selected band so earlier/later lines stay fully dimmed by the
        " whole-line patterns above.
        if a:sc > 1
            call s:add_pattern('\%>' . (a:sl - 1) . 'l\%<' . (a:el + 1) . 'l\%<' . a:sc . 'c.')
        endif
        call s:add_pattern('\%>' . (a:sl - 1) . 'l\%<' . (a:el + 1) . 'l\%>' . a:ec . 'c.')
        return
    endif

    if a:sl == a:el
        if a:sc > 1
            call s:add_pattern('\%' . a:sl . 'l\%<' . a:sc . 'c.')
        endif
        call s:add_pattern('\%' . a:sl . 'l\%>' . a:ec . 'c.')
    else
        if a:sc > 1
            call s:add_pattern('\%' . a:sl . 'l\%<' . a:sc . 'c.')
        endif
        call s:add_pattern('\%' . a:el . 'l\%>' . a:ec . 'c.')
    endif
endfunction

" ── CoC cursor-highlight suppression ─────────────────────────────────────────

function! s:disable_coc() abort
    if !s:coc_disabled
        match none
        let s:saved_eventignore = &eventignore
        set eventignore+=CursorHold,CursorHoldI,CursorMoved,CursorMovedI
        let s:coc_disabled = 1
    endif
endfunction

function! s:enable_coc() abort
    if s:coc_disabled
        let &eventignore = s:saved_eventignore
        let s:coc_disabled = 0
    endif
endfunction

" ── Core operations ──────────────────────────────────────────────────────────

function! s:apply_at_coords(sl, sc, el, ec, block) abort
    call spotlight#clear()
    call s:disable_coc()

    " Buffer-local marks so positions track as the buffer is edited
    call setpos("'s", [0, a:sl, a:sc, 0])
    call setpos("'e", [0, a:el, a:ec, 0])

    let l:state = s:get_state()
    let l:state.active = 1
    let l:state.selection = [a:sl, a:sc, a:el, a:ec]
    let l:state.blockwise = a:block
    call s:set_state(l:state)

    call s:apply_patterns(a:sl, a:sc, a:el, a:ec, a:block)
endfunction

function! spotlight#apply_visual() abort
    " For a block selection the corner columns may be reversed depending on
    " which way it was dragged, so normalise to left/right before lighting up.
    if visualmode() ==# "\<C-v>"
        let l:lc = min([col("'<"), col("'>")])
        let l:rc = max([col("'<"), col("'>")])
        call s:apply_at_coords(line("'<"), l:lc, line("'>"), l:rc, 1)
    else
        call s:apply_at_coords(line("'<"), col("'<"), line("'>"), col("'>"), 0)
    endif
endfunction

function! spotlight#dim_lines(line1, line2) abort
    let l:ec = max([1, len(getline(a:line2))])
    call s:apply_at_coords(a:line1, 1, a:line2, l:ec, 0)
endfunction

function! spotlight#toggle_visual() abort
    if s:get_state().active
        call spotlight#clear()
    else
        call spotlight#apply_visual()
    endif
endfunction

function! spotlight#clear() abort
    call s:clear_window_matches()
    call s:clear_state()
    call s:enable_coc()
    silent! delmarks s e
endfunction

function! spotlight#operator(type) abort
    let l:sl = line("'[")
    let l:el = line("']")
    if a:type ==# 'line'
        call spotlight#dim_lines(l:sl, l:el)
    elseif a:type ==# 'block'
        let l:lc = min([col("'["), col("']")])
        let l:rc = max([col("'["), col("']")])
        call s:apply_at_coords(l:sl, l:lc, l:el, l:rc, 1)
    else
        " char-wise — use exact column bounds so the delimiters of
        " i{ / i( / it themselves end up dimmed
        call s:apply_at_coords(l:sl, col("'["), l:el, col("']"), 0)
    endif
endfunction

" Smart entry point: if a spotlight is active, clear it; otherwise start the
" operator. Prevents the double-press footgun where the second <leader>h is
" parsed as a motion inside operator-pending mode.
function! spotlight#maybe_clear() abort
    if s:get_state().active
        call spotlight#clear()
        return ''
    endif
    let &operatorfunc = 'spotlight#operator'
    return 'g@'
endfunction

" ── Lifecycle hooks (called from plugin/spotlight.vim autocmds) ──────────────

function! spotlight#update() abort
    let l:state = s:get_state()
    if !l:state.active
        return
    endif

    let l:sp = getpos("'s")
    let l:ep = getpos("'e")
    if l:sp[1] == 0 || l:ep[1] == 0
        return
    endif

    let l:state.selection = [l:sp[1], l:sp[2], l:ep[1], l:ep[2]]
    call s:set_state(l:state)

    call s:clear_window_matches()
    call s:apply_patterns(l:sp[1], l:sp[2], l:ep[1], l:ep[2], get(l:state, 'blockwise', 0))
endfunction

" Always wipe any SpotlightDim matches in this window first — handles the
" case where WinEnter fires before bufnr('%') reflects the incoming buffer,
" causing patterns from another buffer's state to leak into this window.
function! spotlight#restore() abort
    call s:clear_window_matches()
    let l:state = s:get_state()
    if l:state.active && len(l:state.selection) == 4
        let l:sel = l:state.selection
        call s:apply_patterns(l:sel[0], l:sel[1], l:sel[2], l:sel[3], get(l:state, 'blockwise', 0))
        call s:disable_coc()
    else
        call s:enable_coc()
    endif
endfunction
