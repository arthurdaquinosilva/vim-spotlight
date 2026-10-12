scriptencoding utf-8
" Block-wise spotlights: screen columns, tabs, wide characters and '$'.

function! Test_block_dims_columns_outside() abort
    call SetLines(['abcdef', 'ghijkl', 'mnopqr', 'stuvwx'])
    call Keys("2G0l\<C-v>jl\\h")
    call assert_equal(['______', '_hi___', '_no___', '______'], Screen())
endfunction

function! Test_block_corners_in_any_direction() abort
    call SetLines(['abcdef', 'ghijkl', 'mnopqr'])
    call Keys("3G0ll\<C-v>kh\\h")
    call assert_equal(['______', '_hi___', '_no___'], Screen())
endfunction

function! Test_block_uses_screen_columns_with_tabs() abort
    " Screen columns 9-10 are 'x ' on line 1 (after a tab) and 'y ' on line 2.
    call SetLines(["\tx = 1", '        y = 2'])
    call Keys("1G0f=h\<C-v>jh\\h")
    call assert_equal(['_x ___', '________y ___'], Screen())
endfunction

function! Test_block_with_multibyte_text() abort
    call SetLines(['éé ab', 'xx cd'])
    call Keys("1G03l\<C-v>jl\\h")
    call assert_equal(['___ab', '___cd'], Screen())
endfunction

function! Test_block_to_end_of_line() abort
    call SetLines(['abc', 'abcdefgh', 'ab', 'zzzz'])
    call Keys("1Gl\<C-v>2j$\\h")
    call assert_equal(['_bc', '_bcdefgh', '_b', '____'], Screen())
endfunction

function! Test_block_follows_inserted_lines() abort
    call RequireTracking()
    call SetLines(['abcd', 'efgh', 'ijkl'])
    call Keys("2G0l\<C-v>jl\\h")
    call Keys("ggOnew\<Esc>")
    call assert_equal(['___', '____', '_fg_', '_jk_'], Screen())
endfunction
