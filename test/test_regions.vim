scriptencoding utf-8
" Several regions: adding (<leader>H), switching off (<leader>Hx) and
" focusing one at a time (]H / [H).

function! Test_add_lights_several_regions() abort
    call SetLines(['one', 'two', 'three', 'four', 'five'])
    2Spotlight
    4SpotlightAdd
    call assert_equal(['___', 'two', '_____', 'four', '____'], Screen())
endfunction

function! Test_add_operator_and_visual() abort
    call SetLines(['one', 'two', 'three', 'four', 'five'])
    call Keys('1G\Hj')
    call Keys('5GV\H')
    call assert_equal(['one', 'two', '_____', '____', 'five'], Screen())
endfunction

function! Test_char_regions_on_the_same_line() abort
    call SetLines(['alpha beta gamma'])
    call Keys('0\Hiw')
    call Keys('$\Hiw')
    call assert_equal('alpha______gamma', Mask(1))
endfunction

function! Test_block_and_char_regions_share_lines() abort
    call SetLines(['abcdefgh', 'abcdefgh', 'abcdefgh'])
    call Keys("1G0l\<C-v>2jl\\H")
    call Keys('2G05l\Hl')
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

function! Test_h_replaces_all_regions_and_bare_h_clears() abort
    call SetLines(['one', 'two', 'three', 'four'])
    1Spotlight
    4SpotlightAdd
    " Visual <leader>h and :Spotlight mean "just this region".
    call Keys('2GVj\h')
    call assert_equal(['___', 'two', 'three', '____'], Screen())
    call assert_equal(1, len(b:spotlight.regions))
    " A bare <leader>h clears every region.
    3SpotlightAdd
    call Keys('\h')
    call assert_false(exists('b:spotlight'))
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
    call Keys('4G\Hx')
    call assert_equal(['___', 'two', '_____', '____', '____'], Screen())
    call Keys('4G\Hx')
    call assert_equal(['___', 'two', '_____', 'four', '____'], Screen())
endfunction

function! Test_toggle_outside_any_region_changes_nothing() abort
    call SetLines(['one', 'two', 'three'])
    2Spotlight
    call Keys('3G\Hx')
    call assert_equal(['___', 'two', '_____'], Screen())
endfunction

function! Test_toggle_picks_innermost_region() abort
    call SetLines(['a', 'b', 'c', 'd', 'e'])
    1,5Spotlight
    3SpotlightAdd
    call Keys('3G\Hx')
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
        call Keys('2G\Hx')
        call assert_equal(['one', 'two', 'three'], Screen())
        call assert_equal(1, &hlsearch)
        " The region is kept: switching it back on lights it again.
        call Keys('2G\Hx')
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
    call Keys(']H')
    call assert_equal(['_', 'b', '_', '_', '_', '_'], Screen())
    call assert_equal(2, line('.'))
    call Keys(']H')
    call assert_equal(['_', '_', '_', '_', 'e', '_'], Screen())
    call assert_equal(5, line('.'))
    " Past the last region: all of them again.
    call Keys(']H')
    call assert_equal(['_', 'b', '_', '_', 'e', '_'], Screen())
    call Keys('[H')
    call assert_equal(['_', '_', '_', '_', 'e', '_'], Screen())
    call Keys('[H[H')
    call assert_equal(['_', 'b', '_', '_', 'e', '_'], Screen())
endfunction

function! Test_focus_skips_regions_switched_off() abort
    call SetLines(['a', 'b', 'c', 'd', 'e'])
    1Spotlight
    3SpotlightAdd
    5SpotlightAdd
    call Keys('3G\Hx')
    call Keys(']H]H')
    call assert_equal(['_', '_', '_', '_', 'e'], Screen())
endfunction

function! Test_toggle_and_add_leave_focus_mode() abort
    call SetLines(['a', 'b', 'c', 'd', 'e'])
    1Spotlight
    3SpotlightAdd
    call Keys(']H')
    call assert_equal(['a', '_', '_', '_', '_'], Screen())
    5SpotlightAdd
    call assert_equal(['a', '_', 'c', '_', 'e'], Screen())
endfunction

function! Test_focus_without_regions_is_harmless() abort
    call SetLines(['a', 'b'])
    call Keys(']H[H\Hx')
    call assert_false(exists('b:spotlight'))
    call assert_equal([], SpotlightMatches())
endfunction

function! Test_region_keys_are_mapped() abort
    call assert_equal('<Plug>(SpotlightAddOperator)', maparg('<leader>H', 'n'))
    call assert_equal('<Plug>(SpotlightAddVisual)', maparg('<leader>H', 'x'))
    call assert_equal('<Plug>(SpotlightToggleRegion)', maparg('<leader>Hx', 'n'))
    call assert_equal('<Plug>(SpotlightNext)', maparg(']H', 'n'))
    call assert_equal('<Plug>(SpotlightPrev)', maparg('[H', 'n'))
endfunction
