scriptencoding utf-8
" Windows, tabs and buffer switching.

function! Test_every_window_on_the_buffer_is_dimmed() abort
    call SetLines(['one', 'two', 'three'])
    let l:first = win_getid()
    split
    let l:second = win_getid()
    2Spotlight
    call assert_equal(['___', 'two', '_____'], Screen(l:first))
    call assert_equal(['___', 'two', '_____'], Screen(l:second))
endfunction

function! Test_edit_in_one_window_updates_the_other() abort
    call RequireTracking()
    call SetLines(['one', 'two', 'three'])
    let l:first = win_getid()
    2Spotlight
    split
    call Keys("1GOnew\<Esc>")
    call assert_equal(['___', '___', 'two', '_____'], Screen(l:first))
endfunction

function! Test_switching_buffer_in_window_drops_matches() abort
    call SetLines(['one', 'two', 'three'])
    let l:buf = bufnr('%')
    2Spotlight
    enew
    call setline(1, ['other', 'buffer'])
    call assert_equal([], SpotlightMatches())
    call assert_equal(['other', 'buffer'], Screen())
    execute 'buffer' l:buf
    call assert_equal(['___', 'two', '_____'], Screen())
endfunction

function! Test_other_buffers_get_no_state() abort
    call SetLines(['one', 'two'])
    2Spotlight
    enew
    call assert_false(exists('b:spotlight'))
    new
    call assert_false(exists('b:spotlight'))
    call assert_equal([], SpotlightMatches())
endfunction

function! Test_new_tab_on_same_buffer() abort
    call SetLines(['one', 'two', 'three'])
    2Spotlight
    let l:buf = bufnr('%')
    tabnew
    execute 'buffer' l:buf
    call assert_equal(['___', 'two', '_____'], Screen())
    tabclose
endfunction

function! Test_clear_removes_matches_from_all_windows() abort
    call SetLines(['one', 'two', 'three'])
    let l:first = win_getid()
    vsplit
    2Spotlight
    SpotlightClear
    call assert_equal([], SpotlightMatches(l:first))
    call assert_equal([], SpotlightMatches())
endfunction

function! Test_wiped_buffer_leaves_no_matches() abort
    call SetLines(['one', 'two', 'three'])
    2Spotlight
    enew
    silent! bwipeout! #
    call assert_equal([], SpotlightMatches())
endfunction
