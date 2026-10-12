scriptencoding utf-8
" Default mappings and <Plug> targets.

function! Test_defaults_are_visual_not_select() abort
    call assert_equal('<Plug>(SpotlightVisual)', maparg('<leader>h', 'x'))
    call assert_equal('', maparg('<leader>h', 's'))
    call assert_equal('<Plug>(SpotlightOperator)', maparg('<leader>h', 'n'))
endfunction

function! Test_normal_key_clears_active_spotlight() abort
    call SetLines(['one', 'two', 'three'])
    2Spotlight
    call Keys('\h')
    call assert_false(exists('b:spotlight'))
    call assert_equal([], SpotlightMatches())
endfunction

function! Test_visual_replaces_existing_spotlight() abort
    call SetLines(['one', 'two', 'three'])
    1Spotlight
    call Keys('3GV\h')
    call assert_equal(['___', '___', 'three'], Screen())
endfunction

function! Test_plug_toggle_keeps_toggle_behaviour() abort
    xmap <buffer> ,t <Plug>(SpotlightToggle)
    call SetLines(['one', 'two', 'three'])
    call Keys('2GV,t')
    call assert_true(exists('b:spotlight'))
    call Keys('3GV,t')
    call assert_false(exists('b:spotlight'))
endfunction

function! s:load_plugin_fresh() abort
    silent! nunmap <leader>h
    silent! xunmap <leader>h
    unlet! g:loaded_spotlight
    runtime plugin/spotlight.vim
endfunction

function! Test_opt_out_of_default_mappings() abort
    let g:spotlight_no_default_mappings = 1
    try
        call s:load_plugin_fresh()
        call assert_equal('', maparg('<leader>h', 'n'))
        call assert_equal('', maparg('<leader>h', 'x'))
    finally
        unlet g:spotlight_no_default_mappings
        call s:load_plugin_fresh()
    endtry
endfunction

function! Test_custom_default_key() abort
    let g:spotlight_mapping = '<leader>s'
    try
        call s:load_plugin_fresh()
        call assert_equal('<Plug>(SpotlightOperator)', maparg('<leader>s', 'n'))
        call assert_equal('', maparg('<leader>h', 'n'))
    finally
        unlet g:spotlight_mapping
        silent! nunmap <leader>s
        silent! xunmap <leader>s
        call s:load_plugin_fresh()
    endtry
endfunction

function! Test_ambiguous_prefix_mapping_is_not_shadowed() abort
    " vim-gitgutter style: <leader>hp etc. would make <leader>h ambiguous.
    nnoremap <leader>hp :let g:hunk_preview = 1<CR>
    try
        call s:load_plugin_fresh()
        call assert_equal('', maparg('<leader>h', 'n'))
        call assert_equal('<Plug>(SpotlightVisual)', maparg('<leader>h', 'x'))
    finally
        nunmap <leader>hp
        call s:load_plugin_fresh()
    endtry
endfunction

function! Test_loads_with_cpo_containing_C() abort
    let l:save = &cpoptions
    try
        set cpoptions+=C
        call s:load_plugin_fresh()
        execute 'source' fnameescape(globpath(&runtimepath, 'autoload/spotlight.vim', 0, 1)[0])
        call SetLines(['one', 'two'])
        2Spotlight
        call assert_equal(['___', 'two'], Screen())
    finally
        let &cpoptions = l:save
    endtry
endfunction
