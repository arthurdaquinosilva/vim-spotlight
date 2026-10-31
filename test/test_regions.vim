scriptencoding utf-8
" Several regions: adding (<leader>h while lit), clearing (<leader>hc),
" removing one (<leader>hd),
" switching off (<leader>hx) and focusing one at a time (<leader>hn / hb).

function! Test_add_lights_several_regions() abort
    call SetLines(['one', 'two', 'three', 'four', 'five'])
    2Spotlight
    4SpotlightAdd
    call assert_equal(['___', 'two', '_____', 'four', '____'], Screen())
endfunction

function! Test_add_operator_and_visual() abort
    call SetLines(['one', 'two', 'three', 'four', 'five'])
    call Keys('1G\hj')
    call Keys('5GV\h')
    call assert_equal(['one', 'two', '_____', '____', 'five'], Screen())
endfunction

function! Test_char_regions_on_the_same_line() abort
    call SetLines(['alpha beta gamma'])
    call Keys('0\hiw')
    call Keys('$\hiw')
    call assert_equal('alpha______gamma', Mask(1))
endfunction

function! Test_block_and_char_regions_share_lines() abort
    call SetLines(['abcdefgh', 'abcdefgh', 'abcdefgh'])
    call Keys("1G0l\<C-v>2jl\\h")
    call Keys('2G05l\hl')
    call assert_equal(['_bc_____', '_bc__f__', '_bc_____'], Screen())
endfunction

function! Test_overlapping_regions_merge() abort
    call SetLines(['1', '2', '3', '4', '5', '6'])
    2,3Spotlight
    3,5SpotlightAdd
    call assert_equal(['_', '2', '3', '4', '5', '_'], Screen())
endfunction

function! Test_every_region_follows_edits() abort
    call RequireDeletionTracking()
    call SetLines(['a', 'b', 'c', 'd', 'e'])
    2Spotlight
    4SpotlightAdd
    call Keys("ggOnew\<Esc>")
    call assert_equal(['___', '_', 'b', '_', 'd', '_'], Screen())
    call Keys('5Gdd')
    call assert_equal(['___', '_', 'b', '_', '_'], Screen())
endfunction

function! Test_h_adds_while_lit_and_hc_clears() abort
    call SetLines(['one', 'two', 'three', 'four'])
    " Nothing lit: <leader>h starts the spotlight; lit: it adds a region.
    call Keys('1G\h_')
    call Keys('3G\hj')
    call assert_equal(['one', '___', 'three', 'four'], Screen())
    call assert_equal(2, len(b:spotlight.regions))
    call Keys('\hc')
    call assert_false(exists('b:spotlight'))
    call assert_equal([], SpotlightMatches())
endfunction

function! Test_spotlight_command_replaces_regions() abort
    call SetLines(['one', 'two', 'three', 'four'])
    1Spotlight
    4SpotlightAdd
    2,3Spotlight
    call assert_equal(['___', 'two', 'three', '____'], Screen())
    call assert_equal(1, len(b:spotlight.regions))
endfunction

function! Test_deleted_region_is_dropped() abort
    call RequireDeletionTracking()
    call SetLines(['a', 'b', 'c', 'd', 'e'])
    2Spotlight
    4SpotlightAdd
    call Keys('2Gdd')
    call assert_equal(['_', '_', 'd', '_'], Screen())
    call assert_equal(1, len(b:spotlight.regions))
endfunction

function! Test_toggle_region_under_cursor() abort
    call SetLines(['one', 'two', 'three', 'four', 'five'])
    2Spotlight
    4SpotlightAdd
    call Keys('4G\hx')
    call assert_equal(['___', 'two', '_____', '____', '____'], Screen())
    call Keys('4G\hx')
    call assert_equal(['___', 'two', '_____', 'four', '____'], Screen())
endfunction

function! Test_toggle_outside_any_region_changes_nothing() abort
    call SetLines(['one', 'two', 'three'])
    2Spotlight
    call Keys('3G\hx')
    call assert_equal(['___', 'two', '_____'], Screen())
endfunction

function! Test_toggle_picks_innermost_region() abort
    call SetLines(['a', 'b', 'c', 'd', 'e'])
    1,5Spotlight
    3SpotlightAdd
    call Keys('3G\hx')
    let l:enabled = map(copy(b:spotlight.regions), 'v:val.enabled')
    call assert_equal([1, 0], l:enabled)
endfunction

function! Test_all_regions_off_dims_nothing_and_restores_options() abort
    let g:spotlight_hide_search = 1
    set hlsearch
    try
        call SetLines(['one', 'two', 'three'])
        2Spotlight
        call assert_equal(0, &hlsearch)
        call Keys('2G\hx')
        call assert_equal(['one', 'two', 'three'], Screen())
        call assert_equal(1, &hlsearch)
        " The region is kept: switching it back on lights it again.
        call Keys('2G\hx')
        call assert_equal(['___', 'two', '_____'], Screen())
    finally
        set hlsearch&
    endtry
endfunction

function! Test_focus_cycles_through_regions() abort
    call SetLines(['a', 'b', 'c', 'd', 'e', 'f'])
    5Spotlight
    2SpotlightAdd
    1
    " Regions are visited in buffer order, whatever order they were added in.
    call Keys('\hn')
    call assert_equal(['_', 'b', '_', '_', '_', '_'], Screen())
    call assert_equal(2, line('.'))
    call Keys('\hn')
    call assert_equal(['_', '_', '_', '_', 'e', '_'], Screen())
    call assert_equal(5, line('.'))
    " Past the last region: all of them again.
    call Keys('\hn')
    call assert_equal(['_', 'b', '_', '_', 'e', '_'], Screen())
    call Keys('\hb')
    call assert_equal(['_', '_', '_', '_', 'e', '_'], Screen())
    call Keys('\hb\hb')
    call assert_equal(['_', 'b', '_', '_', 'e', '_'], Screen())
endfunction

function! Test_focus_visits_regions_switched_off() abort
    call SetLines(['a', 'b', 'c', 'd', 'e'])
    " Select a region, park it with <leader>hx, select another.
    1Spotlight
    call Keys('1G\hx')
    3SpotlightAdd
    call assert_equal(['_', '_', 'c', '_', '_'], Screen())
    call Keys('5G\hn')
    call assert_equal(['a', '_', '_', '_', '_'], Screen())
    call assert_equal(1, line('.'))
    call Keys('\hn')
    call assert_equal(['_', '_', 'c', '_', '_'], Screen())
    call assert_equal(3, line('.'))
    " Past the last one: the enabled regions again.
    call Keys('\hn')
    call assert_equal(['_', '_', 'c', '_', '_'], Screen())
    call Keys('\hb')
    call assert_equal(['_', '_', 'c', '_', '_'], Screen())
    call Keys('\hb')
    call assert_equal(['a', '_', '_', '_', '_'], Screen())
    call assert_true(b:spotlight.regions[0].enabled == 0)
endfunction

function! Test_toggle_and_add_leave_focus_mode() abort
    call SetLines(['a', 'b', 'c', 'd', 'e'])
    1Spotlight
    3SpotlightAdd
    call Keys('\hn')
    call assert_equal(['a', '_', '_', '_', '_'], Screen())
    5SpotlightAdd
    call assert_equal(['a', '_', 'c', '_', 'e'], Screen())
endfunction

function! Test_focus_without_regions_is_harmless() abort
    call SetLines(['a', 'b'])
    call Keys('\hn\hb\hx')
    call assert_false(exists('b:spotlight'))
    call assert_equal([], SpotlightMatches())
endfunction

function! Test_region_keys_are_mapped() abort
    call assert_equal('<Plug>(SpotlightClear)', maparg('<leader>hc', 'n'))
    call assert_equal('<Plug>(SpotlightDeleteRegion)', maparg('<leader>hd', 'n'))
    call assert_equal('<Plug>(SpotlightToggleRegion)', maparg('<leader>hx', 'n'))
    call assert_equal('<Plug>(SpotlightNext)', maparg('<leader>hn', 'n'))
    call assert_equal('<Plug>(SpotlightPrev)', maparg('<leader>hb', 'n'))
endfunction

function! Test_delete_region_under_cursor_keeps_the_others() abort
    call SetLines(['one', 'two', 'three', 'four', 'five'])
    2Spotlight
    4SpotlightAdd
    call Keys('4G\hd')
    call assert_equal(['___', 'two', '_____', '____', '____'], Screen())
    call assert_equal(1, len(b:spotlight.regions))
    " Gone for good: <leader>hx there finds nothing to switch back on.
    call Keys('4G\hx')
    call assert_equal(['___', 'two', '_____', '____', '____'], Screen())
endfunction

function! Test_delete_picks_innermost_region() abort
    call SetLines(['a', 'b', 'c', 'd', 'e'])
    1,5Spotlight
    3SpotlightAdd
    call Keys('3G\hd')
    call assert_equal(1, len(b:spotlight.regions))
    call assert_equal([1, 5], [b:spotlight.regions[0].pos[0],
        \ b:spotlight.regions[0].pos[2]])
endfunction

function! Test_delete_removes_the_focused_region() abort
    call SetLines(['a', 'b', 'c', 'd', 'e', 'f'])
    2Spotlight
    4SpotlightAdd
    6SpotlightAdd
    call Keys('1G\hn\hn')
    call assert_equal(['_', '_', '_', 'd', '_', '_'], Screen())
    " The focused region goes even with the cursor moved off it; every
    " remaining region is lit again.
    call Keys('6G\hd')
    call assert_equal(['_', 'b', '_', '_', '_', 'f'], Screen())
    call assert_equal(0, b:spotlight.focus)
    call Keys('\hn')
    call assert_equal(['_', 'b', '_', '_', '_', '_'], Screen())
endfunction

function! Test_delete_works_on_switched_off_region() abort
    call SetLines(['one', 'two', 'three'])
    1Spotlight
    3SpotlightAdd
    call Keys('3G\hx3G\hd')
    call assert_equal(['one', '___', '_____'], Screen())
    call assert_equal(1, len(b:spotlight.regions))
endfunction

function! Test_delete_last_region_clears() abort
    call SetLines(['one', 'two', 'three'])
    2Spotlight
    call Keys('2G\hd')
    call assert_false(exists('b:spotlight'))
    call assert_equal([], SpotlightMatches())
endfunction

function! Test_delete_outside_any_region_changes_nothing() abort
    call SetLines(['one', 'two', 'three'])
    2Spotlight
    call Keys('3G\hd')
    call assert_equal(['___', 'two', '_____'], Screen())
    call assert_equal(1, len(b:spotlight.regions))
    SpotlightClear
    call Keys('\hd')
    call assert_false(exists('b:spotlight'))
endfunction

function! Test_deleted_region_stops_tracking_edits() abort
    call RequireTracking()
    call SetLines(['a', 'b', 'c', 'd'])
    2Spotlight
    4SpotlightAdd
    call Keys('2G\hd')
    call Keys("ggOnew\<Esc>")
    call assert_equal(['___', '_', '_', '_', 'd'], Screen())
    call assert_equal(1, len(b:spotlight.regions))
endfunction

function! Test_focus_puts_cursor_on_first_character() abort
    call SetLines(['x', '    indented', "\tab", 'one two three', 'abcdefgh'])
    2Spotlight
    call Keys('3G\hj')
    call Keys('4G0w\hiw')
    call Keys("5G03l\<C-v>l\\h")
    call Keys('1G\hn')
    call assert_equal([2, 5], [line('.'), col('.')])
    call Keys('\hn')
    call assert_equal([3, 2], [line('.'), col('.')])
    call Keys('\hn')
    call assert_equal([4, 5], [line('.'), col('.')])
    call Keys('\hn')
    call assert_equal([5, 4], [line('.'), col('.')])
    call Keys('\hb')
    call assert_equal([4, 5], [line('.'), col('.')])
endfunction
