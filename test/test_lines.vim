scriptencoding utf-8
" Line-wise spotlights: :Spotlight, line motions, linewise Visual.

function! Test_command_range_dims_outside_lines() abort
    call SetLines(['one', 'two', 'three', 'four', 'five'])
    3,4Spotlight
    call assert_equal(['___', '___', 'three', 'four', '____'], Screen())
endfunction

function! Test_command_defaults_to_current_line() abort
    call SetLines(['one', 'two', 'three'])
    2
    Spotlight
    call assert_equal(['___', 'two', '_____'], Screen())
endfunction

function! Test_command_bang_and_clear_remove_everything() abort
    call SetLines(['one', 'two', 'three'])
    2Spotlight
    Spotlight!
    call assert_equal([], SpotlightMatches())
    call assert_false(exists('b:spotlight'))
    2Spotlight
    SpotlightClear
    call assert_equal([], SpotlightMatches())
endfunction

function! Test_commands_accept_bar() abort
    call SetLines(['one', 'two', 'three'])
    2Spotlight | let g:after_bar = 1
    call assert_equal(1, g:after_bar)
    SpotlightClear | let g:after_bar = 2
    call assert_equal(2, g:after_bar)
    unlet g:after_bar
endfunction

function! Test_text_appended_to_last_line_stays_lit() abort
    call SetLines(['one', 'two', 'three'])
    1,2Spotlight
    call Keys("2GA more text\<Esc>")
    call assert_equal('two more text', Mask(2))
    call assert_equal('_____', Mask(3))
endfunction

function! Test_region_follows_lines_inserted_above() abort
    call RequireTracking()
    call SetLines(['one', 'two', 'three', 'four'])
    3,4Spotlight
    call Keys("1GOnew 1\<CR>new 2\<Esc>")
    call assert_equal(['_____', '_____', '___', '___', 'three', 'four'], Screen())
endfunction

function! Test_region_survives_deleting_its_first_line() abort
    call RequireTracking()
    call SetLines(['one', 'two', 'three', 'four', 'five'])
    2,4Spotlight
    call Keys('2Gdd')
    call assert_equal(['___', 'three', 'four', '____'], Screen())
    call Keys('u')
    call assert_equal(['___', 'two', 'three', 'four', '____'], Screen())
endfunction

function! Test_region_survives_deleting_its_last_line() abort
    call RequireTracking()
    call SetLines(['one', 'two', 'three', 'four', 'five'])
    2,4Spotlight
    call Keys('4Gdd')
    call assert_equal(['___', 'two', 'three', '____'], Screen())
endfunction

function! Test_lines_added_inside_region_are_lit() abort
    call RequireTracking()
    call SetLines(['one', 'two', 'three', 'four'])
    2,3Spotlight
    call Keys("2Goinside\<Esc>")
    call assert_equal(['___', 'two', 'inside', 'three', '____'], Screen())
endfunction

function! Test_linewise_visual() abort
    call SetLines(['one', 'two', 'three', 'four'])
    call Keys("2GVj\\h")
    call assert_equal(['___', 'two', 'three', '____'], Screen())
endfunction

function! Test_operator_with_line_motion() abort
    call SetLines(['one', 'two', 'three', 'four', 'five'])
    call Keys('2G\h2j')
    call assert_equal(['___', 'two', 'three', 'four', '____'], Screen())
endfunction

function! Test_operator_with_count_and_paragraph() abort
    call SetLines(['a', 'b', '', 'c', 'd', '', 'e'])
    call Keys('4G\hap')
    call assert_equal(['_', '_', '', 'c', 'd', '', '_'], Screen())
endfunction

function! Test_edits_from_another_buffer_api_are_picked_up() abort
    call SetLines(['one', 'two', 'three'])
    2,3Spotlight
    call append(3, 'appended by a plugin')
    " Even before any refresh, lines past the region are dimmed.
    call assert_equal('____________________', Mask(4))
endfunction

function! Test_lost_anchor_falls_back_to_last_position() abort
    if has('nvim') && !has('nvim-0.10')
        throw 'Skipped: extmark invalidation needs Neovim 0.10'
    endif
    call SetLines(['one', 'two', 'three', 'four'])
    2,3Spotlight
    " Replacing every line (like :%!fmt or :edit!) wipes the anchor.
    silent %delete _
    call setline(1, ['ONE', 'TWO', 'THREE', 'FOUR'])
    call spotlight#refresh()
    call assert_equal(['___', 'TWO', 'THREE', '____'], Screen())
endfunction

function! Test_line_opened_below_region_is_outside() abort
    call RequireTracking()
    call SetLines(['one', 'two', 'three'])
    1,2Spotlight
    call Keys("2Gobelow\<Esc>")
    call assert_equal(['one', 'two', '_____', '_____'], Screen())
endfunction

function! Test_line_opened_above_region_is_outside() abort
    call RequireTracking()
    call SetLines(['one', 'two', 'three'])
    2,3Spotlight
    call Keys("2GOabove\<Esc>")
    call assert_equal(['___', '_____', 'two', 'three'], Screen())
endfunction

function! Test_region_tracked_through_mixed_edits() abort
    " Lines added above and removed below in one go: the net line-count
    " change no longer predicts where the region went, forcing a search.
    call RequireTracking()
    call SetLines(['a', 'b', 'c', 'd', 'e', 'f'])
    3,4Spotlight
    call Keys("ggOx\<CR>y\<Esc>Gdd")
    call assert_equal(['_', '_', '_', '_', 'c', 'd', '_'], Screen())
endfunction
