scriptencoding utf-8
" The SpotlightDim highlight group.

" OptionSet is not fired while the test runner executes during startup, so
" fire it explicitly (running it twice is harmless).
function! s:set_bg(value) abort
    execute 'set background=' . a:value
    silent doautocmd <nomodeline> OptionSet background
endfunction

function! s:fg() abort
    let l:id = hlID('SpotlightDim')
    return [synIDattr(l:id, 'fg', 'cterm'), synIDattr(l:id, 'fg#', 'gui')]
endfunction

function! Test_dark_and_light_defaults() abort
    call s:set_bg('dark')
    call assert_equal(['234', '#1c1c1c'], s:fg())
    call s:set_bg('light')
    call assert_equal(['255', '#eeeeee'], s:fg())
    call s:set_bg('dark')
    call assert_equal(['234', '#1c1c1c'], s:fg())
endfunction

function! Test_user_colors_survive_background_change() abort
    highlight SpotlightDim ctermfg=240 guifg=#3a3a3a
    try
        call s:set_bg('light')
        call assert_equal(['240', '#3a3a3a'], s:fg())
    finally
        highlight clear SpotlightDim
        call s:set_bg('dark')
    endtry
endfunction

function! Test_user_link_is_respected() abort
    highlight! link SpotlightDim Comment
    try
        call s:set_bg('light')
        doautocmd <nomodeline> ColorScheme
        call assert_equal(hlID('Comment'), synIDtrans(hlID('SpotlightDim')))
    finally
        highlight! link SpotlightDim NONE
        highlight clear SpotlightDim
        call s:set_bg('dark')
    endtry
endfunction

function! Test_reapplied_after_colorscheme_clears_it() abort
    highlight clear SpotlightDim
    doautocmd <nomodeline> ColorScheme
    call assert_equal(['234', '#1c1c1c'], s:fg())
endfunction
