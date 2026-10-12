scriptencoding utf-8
" test/run.vim — dependency-free test runner for Vim and Neovim.
"
"   vim  -Nu NONE -i NONE -n --not-a-term -S test/run.vim </dev/null
"   nvim --clean --headless -S test/run.vim </dev/null
"
" Sources every test/test_*.vim and runs each Test_* function in a fresh
" buffer (only those matching the regex $SPOTLIGHT_TEST_FILTER, when set).
" A test that throws 'Skipped: <reason>' is reported as skipped.
" Writes a TAP report to $SPOTLIGHT_TEST_LOG (default test/results.tap) and
" exits non-zero when anything fails. `make test` wraps all of this.

set noswapfile nobackup nowritebackup hidden
set shortmess+=I
let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
let &runtimepath = s:root . ',' . &runtimepath
let g:mapleader = '\'
filetype off
syntax off

execute 'source' fnameescape(s:root . '/test/helpers.vim')
runtime plugin/spotlight.vim

" Runs during startup (from -S), not on VimEnter: without a terminal on stdin
" Vim may hit EOF and quit before VimEnter fires, which makes CI flaky.
" OptionSet is not fired during startup, so tests trigger it by hand.
function! s:run() abort
    let l:log = empty($SPOTLIGHT_TEST_LOG)
        \ ? s:root . '/test/results.tap' : $SPOTLIGHT_TEST_LOG
    let l:out = []
    let l:failed = 0
    let l:count = 0

    for l:file in sort(glob(s:root . '/test/test_*.vim', 0, 1))
        let l:before = split(execute('function /^Test_'), "\n")
        execute 'source' fnameescape(l:file)
        let l:names = filter(split(execute('function /^Test_'), "\n"),
            \ 'index(l:before, v:val) < 0')
        let l:names = sort(map(l:names, 'matchstr(v:val, ''Test_\w\+'')'))
        if !empty($SPOTLIGHT_TEST_FILTER)
            call filter(l:names, 'v:val =~# $SPOTLIGHT_TEST_FILTER')
        endif
        call add(l:out, '# ' . fnamemodify(l:file, ':t'))

        for l:name in l:names
            let l:count += 1
            " Written before each test so a crash or hang names the culprit.
            call writefile(l:out + ['# running ' . l:name], l:log)
            let v:errors = []
            let l:skip = ''
            call ResetEditor()
            try
                call call(l:name, [])
            catch /^Skipped:/
                let l:skip = matchstr(v:exception, '^Skipped:\s*\zs.*')
            catch
                call add(v:errors, 'Exception: ' . v:exception . ' @ ' . v:throwpoint)
            endtry
            if !empty(l:skip)
                call add(l:out, 'ok ' . l:count . ' - ' . l:name . ' # SKIP ' . l:skip)
            elseif empty(v:errors)
                call add(l:out, 'ok ' . l:count . ' - ' . l:name)
            else
                let l:failed += 1
                call add(l:out, 'not ok ' . l:count . ' - ' . l:name)
                call extend(l:out, map(copy(v:errors), '"#   " . v:val'))
            endif
            execute 'delfunction' l:name
        endfor
    endfor

    let l:editor = has('nvim')
        \ ? 'Neovim ' . matchstr(execute('version'), 'NVIM v\zs[^ \n]*')
        \ : 'Vim ' . (v:version / 100) . '.' . (v:version % 100)
    call insert(l:out, '1..' . l:count)
    call insert(l:out, '# ' . l:editor)
    call add(l:out, printf('# %d/%d passed', l:count - l:failed, l:count))
    call writefile(l:out, l:log)

    if l:failed || l:count == 0
        cquit!
    endif
    qall!
endfunction

call s:run()
