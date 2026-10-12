scriptencoding utf-8
" Startup cost: the autoload script must not be loaded until it is needed.
" Runs in a child editor so the result is not affected by other tests.

function! Test_autoload_not_loaded_by_buffer_and_window_events() abort
    let l:root = fnamemodify(globpath(&runtimepath, 'plugin/spotlight.vim', 0, 1)[0], ':h:h')
    let l:out = tempname()
    let l:script = tempname()
    call writefile([
        \ 'set rtp^=' . fnameescape(l:root),
        \ 'runtime plugin/spotlight.vim',
        \ 'edit ' . fnameescape(l:out . '.a'),
        \ 'split | new | wincmd w | tabnew',
        \ 'call writefile([execute("scriptnames") =~# "autoload.spotlight\\.vim" ? "loaded" : "lazy"], '
        \     . string(l:out) . ')',
        \ 'qall!',
        \ ], l:script)
    let l:cmd = has('nvim')
        \ ? [v:progpath, '--clean', '--headless', '-S', l:script]
        \ : [v:progpath, '-Nu', 'NONE', '-i', 'NONE', '-n', '-es', '-S', l:script]
    call system(join(map(l:cmd, 'shellescape(v:val)')))
    call assert_equal(['lazy'], readfile(l:out))
endfunction
