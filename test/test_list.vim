scriptencoding utf-8
" The region list (<leader>hq): a location list of the regions, whose entries
" light their region when chosen.

function! s:make_regions() abort
    call SetLines(['first', '    second', 'third', "\tfourth", 'fifth'])
    2Spotlight
    4SpotlightAdd
endfunction

function! s:entries() abort
    return map(getloclist(0), '[v:val.lnum, v:val.col, v:val.text]')
endfunction

function! Test_list_shows_regions_in_buffer_order() abort
    call SetLines(['first', '    second', 'third', "\tfourth", 'fifth'])
    4Spotlight
    2SpotlightAdd
    call Keys('\hq')
    call assert_equal('qf', &filetype)
    call assert_equal([[2, 5, 'second'], [4, 2, 'fourth']], s:entries())
    call assert_equal('Spotlight regions', getloclist(0, {'title': 1}).title)
endfunction

function! Test_list_shows_only_the_file_name() abort
    silent file some/long/path/name.js
    call s:make_regions()
    call Keys('\hq')
    if !has_key(getloclist(0)[0], 'module')
        return
    endif
    call assert_equal('name.js', getloclist(0)[0].module)
    call assert_match('^name.js|2 col 5| second', getline(1))
endfunction

function! Test_list_leaves_quickfix_alone() abort
    call setqflist([{'filename': 'x', 'lnum': 1, 'text': 'mine'}])
    call s:make_regions()
    call Keys('\hq')
    call assert_equal(['mine'], map(getqflist(), 'v:val.text'))
    call setqflist([])
endfunction

function! Test_list_enter_lights_the_region_and_moves_there() abort
    call s:make_regions()
    let l:code = win_getid()
    1
    call Keys('\hq')
    call Keys("2G\<CR>")
    call assert_equal(l:code, win_getid())
    call assert_equal(['_____', '__________', '_____', "\tfourth", '_____'], Screen())
    call assert_equal([4, 2], [line('.'), col('.')])
    call assert_equal(2, b:spotlight.focus)
endfunction

function! Test_list_selection_carries_on_with_the_other_keys() abort
    call s:make_regions()
    call Keys('\hq')
    call Keys("2G\<CR>")
    call Keys('\hn')
    call assert_equal([2, 5], [line('.'), col('.')])
    call assert_equal(['_____', '    second', '_____', '_______', '_____'], Screen())
    call Keys('\hx')
    call assert_equal(0, b:spotlight.focus)
    call assert_equal([], SpotlightMatches())
endfunction

function! Test_list_selection_works_on_a_switched_off_region() abort
    call s:make_regions()
    call Keys('\hx')
    call Keys('\hq')
    call Keys("\<CR>")
    call assert_equal(['_____', '    second', '_____', '_______', '_____'], Screen())
endfunction

function! Test_list_covers_every_region_mode() abort
    call SetLines(['one two three', 'abcdefgh'])
    call Keys('1G0w\hiw')
    call Keys("2G03l\<C-v>l\\h")
    call Keys('\hq')
    call assert_equal([[1, 5, 'one two three'], [2, 4, 'abcdefgh']], s:entries())
    call Keys("2G\<CR>")
    call assert_equal([2, 4], [line('.'), col('.')])
endfunction

function! Test_list_mappings_cover_double_click() abort
    call s:make_regions()
    call Keys('\hq')
    call assert_match('spotlight#list_select', maparg('<CR>', 'n'))
    call assert_match('spotlight#list_select', maparg('<2-LeftMouse>', 'n'))
endfunction

function! Test_list_follows_added_and_removed_regions() abort
    call s:make_regions()
    let l:code = win_getid()
    call Keys('\hq')
    call win_gotoid(l:code)
    5SpotlightAdd
    call assert_equal([2, 4, 5], map(getloclist(0), 'v:val.lnum'))
    call Keys('4G\hd')
    call assert_equal([2, 5], map(getloclist(0), 'v:val.lnum'))
    " Entries still lead to the right regions.
    lopen
    call Keys("2G\<CR>")
    call assert_equal(5, line('.'))
    call assert_equal(['_____', '__________', '_____', '_______', 'fifth'], Screen())
    call Keys('\hc')
    call assert_equal([], getloclist(0))
endfunction

function! Test_list_follows_edits() abort
    call RequireTracking()
    call s:make_regions()
    let l:code = win_getid()
    call Keys('\hq')
    call win_gotoid(l:code)
    call Keys("ggOnew\<Esc>")
    call assert_equal([3, 5], map(getloclist(0), 'v:val.lnum'))
endfunction

function! Test_list_reopened_by_hand_still_lights_regions() abort
    call s:make_regions()
    call Keys('\hq')
    lclose
    lopen
    call Keys("2G\<CR>")
    call assert_equal(['_____', '__________', '_____', "\tfourth", '_____'], Screen())
endfunction

function! Test_another_list_in_the_window_behaves_as_usual() abort
    call s:make_regions()
    let l:code = win_getid()
    call Keys('\hq')
    call win_gotoid(l:code)
    call setloclist(0, [{'bufnr': bufnr('%'), 'lnum': 3, 'text': 'other'}], ' ')
    lopen
    call Keys("\<CR>")
    call assert_equal(3, line('.'))
    call assert_equal(0, b:spotlight.focus)
endfunction

function! Test_list_without_regions_is_harmless() abort
    call SetLines(['a', 'b'])
    let l:win = win_getid()
    call Keys('\hq')
    call assert_equal(l:win, win_getid())
    call assert_equal([], getloclist(0))
endfunction

function! Test_list_window_is_not_dimmed() abort
    call s:make_regions()
    call Keys('\hq')
    call assert_equal([], SpotlightMatches())
endfunction

function! Test_list_key_is_mapped() abort
    call assert_equal('<Plug>(SpotlightList)', maparg('<leader>hq', 'n'))
endfunction
