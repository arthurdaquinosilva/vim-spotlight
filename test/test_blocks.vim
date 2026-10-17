scriptencoding utf-8
" <leader>hd: the indented block around the cursor, zooming out / in.

let s:js = [
    \ 'function load() {',
    \ '  if (ok) {',
    \ '    for (x of xs) {',
    \ '      use(x)',
    \ '',
    \ '      more(x)',
    \ '    }',
    \ '  }',
    \ '}',
    \ 'function save() {',
    \ '  x',
    \ '}',
    \ ]

" Line numbers that are lit (non-blank lines only).
function! s:lit() abort
    let l:lit = []
    for l:lnum in range(1, line('$'))
        let l:mask = Mask(l:lnum)
        if !empty(l:mask) && l:mask !~# '^_*$'
            call add(l:lit, l:lnum)
        endif
    endfor
    return l:lit
endfunction

function! Test_innermost_block_around_cursor() abort
    call SetLines(s:js)
    call Keys('4G\hd')
    " The for block, its blank line and its closing brace.
    call assert_equal([3, 4, 6, 7], s:lit())
endfunction

function! Test_zoom_out_and_back_in() abort
    call SetLines(s:js)
    call Keys('4G\hd')
    call Keys('\hn')
    call assert_equal([2, 3, 4, 6, 7, 8], s:lit())
    call Keys('\hn')
    call assert_equal([1, 2, 3, 4, 6, 7, 8, 9], s:lit())
    " Already at the outermost block: nothing changes.
    call Keys('\hn')
    call assert_equal([1, 2, 3, 4, 6, 7, 8, 9], s:lit())
    call Keys('\hb\hb')
    call assert_equal([3, 4, 6, 7], s:lit())
    " The cursor stays where it was.
    call assert_equal(4, line('.'))
endfunction

function! Test_header_and_closing_lines_pick_their_block() abort
    call SetLines(s:js)
    call Keys('2G\hd')
    call assert_equal([2, 3, 4, 6, 7, 8], s:lit())
    call Keys('8G\hd')
    call assert_equal([2, 3, 4, 6, 7, 8], s:lit())
endfunction

function! Test_indentation_without_closers() abort
    call SetLines(['def f():', '    if x:', '        a', '', '        b',
        \ '    return c', '', 'g()'])
    call Keys('3G\hd')
    call assert_equal([2, 3, 5], s:lit())
    call Keys('\hn')
    call assert_equal([1, 2, 3, 5, 6], s:lit())
endfunction

function! Test_no_block_at_top_level_line() abort
    call SetLines(['a', 'b'])
    call Keys('\hd')
    call assert_false(exists('b:spotlight'))
endfunction

function! Test_adding_a_region_leaves_zoom_mode() abort
    call SetLines(s:js)
    call Keys('4G\hd')
    11SpotlightAdd
    " All regions lit again; n / b walk regions instead of zooming.
    call assert_equal([1, 2, 3, 4, 6, 7, 8, 9, 11], s:lit())
    call Keys('\hn')
    call assert_equal(1, line('.'))
endfunction

function! Test_blocks_key_is_mapped() abort
    call assert_equal('<Plug>(SpotlightBlocks)', maparg('<leader>hd', 'n'))
endfunction

function! Test_jsx_self_closing_tag_keeps_its_closer() abort
    call SetLines(['<form>', '  <input', '    value={x}', '  />', '</form>'])
    call Keys('3G\hd')
    call assert_equal([2, 3, 4], s:lit())
endfunction
