scriptencoding utf-8
" Character-wise spotlights: text objects, charwise Visual, multibyte text.

function! Test_inner_braces_keep_delimiters_dim() abort
    call SetLines(['if (x) { return y; } else'])
    call Keys('0f{l\hi{')
    call assert_equal('________ return y; ______', Mask(1))
endfunction

function! Test_around_parens_includes_them() abort
    call SetLines(['call(a, b) + 1'])
    call Keys('0f(l\ha(')
    call assert_equal('____(a, b)____', Mask(1))
endfunction

function! Test_inner_word() abort
    call SetLines(['alpha beta gamma'])
    call Keys('0w\hiw')
    call assert_equal('______beta______', Mask(1))
endfunction

function! Test_multiline_charwise_dims_partial_edges() abort
    call SetLines(['first line', 'second line', 'third line'])
    call Keys('1G0wv2Gw\h')
    call assert_equal(['______line', 'second l___', '__________'], Screen())
endfunction

function! Test_multibyte_last_character_is_lit() abort
    call SetLines(['ação então'])
    call Keys('0\hiw')
    call assert_equal('ação______', Mask(1))
endfunction

function! Test_selection_exclusive() abort
    set selection=exclusive
    call SetLines(['abcdef'])
    call Keys('0lv2l\h')
    call assert_equal('_bc___', Mask(1))
endfunction

function! Test_typing_at_end_of_region_extends_it() abort
    call RequireTracking()
    call SetLines(['alpha beta gamma'])
    call Keys('0w\hiw')
    call Keys("ea!!\<Esc>")
    call assert_equal('______beta!!______', Mask(1))
endfunction

function! Test_typing_before_region_shifts_it() abort
    call RequireTracking()
    call SetLines(['alpha beta gamma'])
    call Keys('0w\hiw')
    call Keys("0i>> \<Esc>")
    call assert_equal('_________beta______', Mask(1))
endfunction

function! Test_dot_repeat_reapplies_operator() abort
    call SetLines(['alpha beta gamma'])
    " One keystroke stream, as typed: a nested feedkeys() would not see the
    " redo buffer the way an interactive '.' does.
    call Keys("0w\\hiw:SpotlightClear\<CR>w.")
    call assert_equal('___________gamma', Mask(1))
endfunction

function! Test_empty_text_object_does_nothing() abort
    call SetLines(['f()'])
    call Keys('0f(\hi(')
    call assert_false(exists('b:spotlight'))
endfunction
