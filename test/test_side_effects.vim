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
