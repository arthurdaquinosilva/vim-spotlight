scriptencoding utf-8
" test/helpers.vim — shared helpers for the test suite.

" Fresh, single-window editor state between tests.
function! ResetEditor() abort
    silent! SpotlightClear
    silent! tabonly!
    silent! only!
    enew!
    silent! %bwipeout!
    set selection& virtualedit& eventignore& background=dark tabstop=8
    unlet! g:spotlight_suppress_cursor_events g:spotlight_priority
    call clearmatches()
endfunction

" Replace the buffer and break the undo sequence so each later edit can be
" undone on its own.
function! SetLines(lines) abort
    silent %delete _
    call setline(1, a:lines)
    let &undolevels = &undolevels
endfunction

" Run keys like a user would, with mappings, then let the edit autocmds run
" (Vim does not fire TextChanged while feedkeys() is still consuming input).
function! Keys(keys) abort
    call feedkeys(a:keys, 'xt')
    silent doautocmd <nomodeline> TextChanged
endfunction

" True when the character at (lnum, col) is covered by a SpotlightDim match in
" window {winid} (default: current).
function! IsDim(lnum, col, ...) abort
    let l:winid = a:0 ? a:1 : win_getid()
    let l:bufnr = winbufnr(l:winid)
    let l:line = getbufline(l:bufnr, a:lnum)[0]
    for l:m in getmatches(l:winid)
        if l:m.group !=# 'SpotlightDim'
            continue
        endif
        let l:pat = '\%' . a:lnum . 'l\%' . a:col . 'c\%(' . l:m.pattern . '\)'
        if s:match_in(l:winid, l:pat)
            return 1
        endif
    endfor
    return 0
endfunction

function! s:match_in(winid, pat) abort
    let l:cur = win_getid()
    noautocmd call win_gotoid(a:winid)
    let l:view = winsaveview()
    call cursor(1, 1)
    let l:hit = search(a:pat, 'cnW') > 0
    call winrestview(l:view)
    noautocmd call win_gotoid(l:cur)
    return l:hit
endfunction

" A picture of one line: each lit character as itself, each dimmed one as '_'.
" Makes assertions read like the screen:  'int _____ = 1;'
function! Mask(lnum, ...) abort
    let l:winid = a:0 ? a:1 : win_getid()
    let l:line = getbufline(winbufnr(l:winid), a:lnum)[0]
    let l:out = ''
    let l:col = 1
    while l:col <= len(l:line)
        let l:ch = matchstr(l:line, '\%' . l:col . 'c.')
        let l:out .= IsDim(a:lnum, l:col, l:winid) ? '_' : l:ch
        let l:col += len(l:ch)
    endwhile
    return l:out
endfunction

" Masks for every line in the window's buffer.
function! Screen(...) abort
    let l:winid = a:0 ? a:1 : win_getid()
    let l:n = len(getbufline(winbufnr(l:winid), 1, '$'))
    return map(range(1, l:n), 'Mask(v:val, l:winid)')
endfunction

function! SpotlightMatches(...) abort
    let l:winid = a:0 ? a:1 : win_getid()
    return filter(getmatches(l:winid), 'v:val.group ==# "SpotlightDim"')
endfunction

" Edit tracking needs text properties (Vim) or extmarks (Neovim); without
" them the region keeps fixed coordinates (documented degraded mode).
function! RequireTracking() abort
    if !has('nvim') && !has('textprop')
        throw 'Skipped: needs +textprop'
    endif
endfunction
