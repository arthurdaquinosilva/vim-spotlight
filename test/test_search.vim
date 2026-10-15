scriptencoding utf-8
" Optional hiding of the search highlight (g:spotlight_hide_search).

function! Test_search_highlight_untouched_by_default() abort
    set hlsearch
    call SetLines(['one', 'two'])
    2Spotlight
    call assert_equal(1, &hlsearch)
endfunction

function! Test_search_highlight_hidden_while_active() abort
    let g:spotlight_hide_search = 1
    set hlsearch
    try
        call SetLines(['foo', 'foo bar', 'foo'])
        2Spotlight
        call assert_equal(0, &hlsearch)
        " Searching and n/N still work, they just don't light up.
        call Keys('2G0*n')
        call assert_equal(0, &hlsearch)
        SpotlightClear
        call assert_equal(1, &hlsearch)
    finally
        unlet g:spotlight_hide_search
        set hlsearch&
    endtry
endfunction

function! Test_search_highlight_back_when_leaving_buffer() abort
    let g:spotlight_hide_search = 1
    set hlsearch
    try
        call SetLines(['one', 'two'])
        let l:buf = bufnr('%')
        2Spotlight
        enew
        call assert_equal(1, &hlsearch)
        execute 'buffer' l:buf
        call assert_equal(0, &hlsearch)
    finally
        unlet g:spotlight_hide_search
        set hlsearch&
    endtry
endfunction

function! Test_user_hlsearch_choice_respected() abort
    " nohlsearch before the spotlight stays off; turning it on meanwhile wins.
    let g:spotlight_hide_search = 1
    try
        set nohlsearch
        call SetLines(['one', 'two'])
        2Spotlight
        SpotlightClear
        call assert_equal(0, &hlsearch)
        set hlsearch
        2Spotlight
        set hlsearch
        SpotlightClear
        call assert_equal(1, &hlsearch)
    finally
        unlet g:spotlight_hide_search
        set hlsearch&
    endtry
endfunction
