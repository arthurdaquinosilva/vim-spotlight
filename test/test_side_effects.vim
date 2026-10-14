scriptencoding utf-8
" The plugin must never touch user state it does not own.

function! Test_user_marks_are_untouched() abort
    call SetLines(['one', 'two', 'three', 'four'])
    call setpos("'s", [0, 4, 2, 0])
    call setpos("'e", [0, 1, 1, 0])
    2,3Spotlight
    call Keys('1GOx')
    SpotlightClear
    call assert_equal([0, 5, 2, 0], getpos("'s"))
    call assert_equal([0, 2, 1, 0], getpos("'e"))
endfunction

function! Test_user_match_is_preserved() abort
    call SetLines(['one ', 'two'])
    highlight SpotlightTestTrailing ctermbg=1
    match SpotlightTestTrailing /\s\+$/
    2Spotlight
    SpotlightClear
    call assert_equal(['SpotlightTestTrailing'], map(getmatches(), 'v:val.group'))
endfunction

function! Test_eventignore_untouched_by_default() abort
    set eventignore=FocusGained
    call SetLines(['one', 'two'])
    2Spotlight
    call assert_equal('FocusGained', &eventignore)
endfunction

function! Test_opt_in_suppression_restores_only_its_events() abort
    let g:spotlight_suppress_cursor_events = 1
    set eventignore=FocusGained,CursorHold
    call SetLines(['one', 'two'])
    let l:buf = bufnr('%')
    2Spotlight
    call assert_equal(sort(['FocusGained', 'CursorHold', 'CursorMoved',
        \ 'CursorMovedI', 'CursorHoldI']), sort(split(&eventignore, ',')))

    " Leaving for a buffer without a spotlight lifts the suppression...
    enew
    call assert_equal('FocusGained,CursorHold', &eventignore)
    " ...and coming back reinstates it.
    execute 'buffer' l:buf
    call assert_match('CursorMoved', &eventignore)

    " User adds an event meanwhile; it must survive the clear.
    set eventignore+=BufRead
    SpotlightClear
    call assert_equal('FocusGained,CursorHold,BufRead', &eventignore)
endfunction

function! Test_buffer_autocmds_removed_on_clear() abort
    call SetLines(['one', 'two'])
    2Spotlight
    call assert_true(exists('#spotlight_buffer#TextChanged#<buffer>'))
    SpotlightClear
    call assert_false(exists('#spotlight_buffer#TextChanged#<buffer>'))
endfunction

function! Test_priority_is_configurable() abort
    let g:spotlight_priority = 42
    call SetLines(['one', 'two'])
    2Spotlight
    call assert_equal([42], uniq(map(SpotlightMatches(), 'v:val.priority')))
endfunction

function! Test_suppression_clears_existing_coc_highlight() abort
    " coc.nvim drew its word highlight before the spotlight went on; with
    " CursorMoved ignored it would never be removed.
    let g:spotlight_suppress_cursor_events = 1
    call SetLines(['setStock: x', 'setStock()', 'other'])
    highlight CocHighlightText ctermbg=238
    call matchaddpos('CocHighlightText', [[1, 1, 8], [2, 1, 8]])
    1,2Spotlight
    call assert_equal([], filter(getmatches(), 'v:val.group =~# "^CocHighlight"'))
endfunction

function! Test_coc_highlight_untouched_without_suppression() abort
    call SetLines(['setStock: x', 'setStock()', 'other'])
    highlight CocHighlightText ctermbg=238
    call matchaddpos('CocHighlightText', [[1, 1, 8]])
    1,2Spotlight
    call assert_equal(['CocHighlightText'],
        \ map(filter(getmatches(), 'v:val.group =~# "^Coc"'), 'v:val.group'))
endfunction

function! Test_suppression_hides_and_restores_match() abort
    " A cursor-word script using :match (updated on CursorMoved) must not
    " leave its highlight frozen on screen while the spotlight is on.
    let g:spotlight_suppress_cursor_events = 1
    highlight SpotlightTestWord ctermbg=238
    call SetLines(['setStock: x', 'setStock()', 'other'])
    match SpotlightTestWord /setStock/
    let g:moved = 0
    augroup spotlight_test_moved
        autocmd!
        autocmd CursorMoved * let g:moved += 1
    augroup END
    try
        1,2Spotlight
        call assert_equal([], filter(getmatches(), 'v:val.id == 1'))
        SpotlightClear
        call assert_equal(['SpotlightTestWord'],
            \ map(filter(getmatches(), 'v:val.id == 1'), 'v:val.group'))
        " Cursor-word scripts get a chance to recompute for the current word.
        call assert_true(g:moved > 0)
    finally
        autocmd! spotlight_test_moved
        augroup! spotlight_test_moved
        unlet g:moved
    endtry
endfunction

function! Test_suppression_restores_match_when_leaving_buffer() abort
    let g:spotlight_suppress_cursor_events = 1
    highlight SpotlightTestWord ctermbg=238
    call SetLines(['one', 'two'])
    match SpotlightTestWord /one/
    2Spotlight
    let l:win = win_getid()
    new
    call assert_equal(['SpotlightTestWord'],
        \ map(filter(getmatches(l:win), 'v:val.id == 1'), 'v:val.group'))
endfunction

function! Test_suppression_removes_coc_highlight_arriving_late() abort
    " coc.nvim asks the language server on CursorHold and draws the answer
    " whenever it arrives, possibly after the spotlight went on.
    if !exists('*timer_start')
        throw 'Skipped: needs +timers'
    endif
    let g:spotlight_suppress_cursor_events = 1
    highlight CocHighlightText ctermbg=238
    call SetLines(['<div>', '  x', '</div>'])
    1,3Spotlight
    call matchaddpos('CocHighlightText', [[1, 2, 3], [3, 3, 3]])
    sleep 300m
    call assert_equal([], filter(getmatches(), 'v:val.group =~# "^CocHighlight"'))
endfunction

function! Test_sweep_stops_when_spotlight_cleared() abort
    if !exists('*timer_start')
        throw 'Skipped: needs +timers'
    endif
    let g:spotlight_suppress_cursor_events = 1
    highlight CocHighlightText ctermbg=238
    call SetLines(['<div>', '  x', '</div>'])
    1,3Spotlight
    SpotlightClear
    call matchaddpos('CocHighlightText', [[1, 2, 3]])
    sleep 300m
    call assert_equal(['CocHighlightText'],
        \ map(filter(getmatches(), 'v:val.group =~# "^Coc"'), 'v:val.group'))
endfunction

function! Test_suppression_hides_matching_pair_highlights() abort
    " vim-matchup (MatchWord/MatchParen) and the built-in matchparen (:3match)
    " update on CursorMoved too, so they would freeze the same way.
    let g:spotlight_suppress_cursor_events = 1
    highlight MatchWord cterm=underline
    highlight MatchParenCur cterm=bold
    highlight MatchParen ctermbg=238
    call SetLines(['<div>', '  x', '</div>'])
    call matchaddpos('MatchWord', [[1, 2, 3], [3, 3, 3]])
    call matchaddpos('MatchParenCur', [[1, 1]])
    3match MatchParen /x/
    1,3Spotlight
    call assert_equal(['SpotlightDim'], uniq(map(getmatches(), 'v:val.group')))
endfunction
