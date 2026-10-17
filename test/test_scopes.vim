scriptencoding utf-8
" <leader>hd: regions from the file's functions, classes and methods.

" Stand-in for coc.nvim's documentSymbols (0-based ranges, as coc returns).
function! s:symbol(kind, first, last) abort
    return {'kind': a:kind, 'text': a:kind, 'lnum': a:first + 1,
        \ 'range': {'start': {'line': a:first, 'character': 0},
        \           'end': {'line': a:last, 'character': 1}}}
endfunction

function! s:fake_coc(symbols) abort
    let g:spotlight_test_symbols = a:symbols
    let g:coc_service_initialized = 1
    function! CocAction(name) abort
        return a:name ==# 'documentSymbols' ? g:spotlight_test_symbols : []
    endfunction
endfunction

function! s:no_coc() abort
    silent! delfunction CocAction
    unlet! g:coc_service_initialized g:spotlight_test_symbols
endfunction

" class Cart { constructor; add }  +  function total
let s:file = ['class Cart {', '  constructor() {', '    x', '  }', '',
    \ '  add(item) {', '    y', '  }', '}', '', 'function total() {',
    \ '  z', '}']

function! s:cart_symbols() abort
    return [s:symbol('Class', 0, 8), s:symbol('Constructor', 1, 3),
        \ s:symbol('Method', 5, 7), s:symbol('Variable', 2, 2),
        \ s:symbol('Function', 10, 12)]
endfunction

function! Test_scopes_focus_innermost_under_cursor() abort
    call s:fake_coc(s:cart_symbols())
    try
        call SetLines(s:file)
        call Keys('7G\hd')
        " One region per class / method / function; variables are ignored.
        call assert_equal(4, len(b:spotlight.regions))
        call assert_equal([0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0],
            \ map(Screen(), 'v:val !~# "^_*$" && !empty(v:val)'))
    finally
        call s:no_coc()
    endtry
endfunction

function! Test_scopes_cycle_in_buffer_order() abort
    call s:fake_coc(s:cart_symbols())
    try
        call SetLines(s:file)
        call Keys('7G\hd')
        call Keys('\hn')
        " After 'add' comes 'total'.
        call assert_equal(11, line('.'))
        call assert_equal('function total() {', Mask(11))
        call assert_equal('_____', Mask(7))
        " Past the last scope everything is lit; then from the top: the class.
        call Keys('\hn\hn')
        call assert_equal(1, line('.'))
        call assert_equal('  add(item) {', Mask(6))
        call assert_equal('_____________', Mask(11)[0:12])
    finally
        call s:no_coc()
    endtry
endfunction

function! Test_scopes_replace_manual_regions() abort
    call s:fake_coc(s:cart_symbols())
    try
        call SetLines(s:file)
        5Spotlight
        call Keys('12G\hd')
        call assert_equal(4, len(b:spotlight.regions))
        call assert_equal('  z', Mask(12))
    finally
        call s:no_coc()
    endtry
endfunction

function! Test_scopes_from_custom_provider() abort
    let g:SpotlightScopeProvider = {-> [[2, 3], [99, 120], [5, 4]]}
    try
        call SetLines(['a', 'b', 'c', 'd', 'e'])
        call Keys('1G\hd')
        " Out-of-range or reversed pairs are ignored; focus goes below.
        call assert_equal(1, len(b:spotlight.regions))
        call assert_equal(['_', 'b', 'c', '_', '_'], Screen())
    finally
        unlet g:SpotlightScopeProvider
    endtry
endfunction

function! Test_scopes_without_source_changes_nothing() abort
    call s:no_coc()
    call SetLines(['a', 'b'])
    call Keys('\hd')
    call assert_false(exists('b:spotlight'))
    call assert_equal('<Plug>(SpotlightScopes)', maparg('<leader>hd', 'n'))
endfunction
