scriptencoding utf-8
" <leader>hd: the indented block around the cursor, walking the blocks inside.

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
    " The for body is split by a blank line: the chunk with the cursor.
    call Keys('4G\hd')
    call assert_equal([4], s:lit())
    call Keys('3G\hd')
    " On the header: the for block, its blank line and its closing brace.
    call assert_equal([3, 4, 6, 7], s:lit())
endfunction

function! Test_walk_blocks_inside_and_back() abort
    call SetLines(s:js)
    call Keys('1G\hd')
    call assert_equal([1, 2, 3, 4, 6, 7, 8, 9], s:lit())
    " Every block inside, nested ones too, in file order.
    call Keys('\hn')
    call assert_equal([2, 3, 4, 6, 7, 8], s:lit())
    call assert_equal(2, line('.'))
    call Keys('\hn')
    call assert_equal([3, 4, 6, 7], s:lit())
    call assert_equal(3, line('.'))
    " Then the two chunks of the for body (split by a blank line).
    call Keys('\hn')
    call assert_equal([4], s:lit())
    call Keys('\hn')
    call assert_equal([6], s:lit())
    " Past the last one: the whole function again.
    call Keys('\hn')
    call assert_equal([1, 2, 3, 4, 6, 7, 8, 9], s:lit())
    " And backwards, wrapping to the last one.
    call Keys('\hb')
    call assert_equal([6], s:lit())
endfunction

function! Test_python_method_from_its_name() abort
    call SetLines([
        \ 'class Shop:',
        \ '    def save(self):',
        \ '        if not self.ok:',
        \ '            log()',
        \ '        for x in xs:',
        \ '            if x:',
        \ '                use(x)',
        \ '        with lock:',
        \ '            flush()',
        \ '',
        \ '    def load(self):',
        \ '        pass',
        \ ])
    call Keys('2G0w\hd')
    call assert_equal([2, 3, 4, 5, 6, 7, 8, 9], s:lit())
    let l:steps = []
    for l:i in range(5)
        call Keys('\hn')
        call add(l:steps, s:lit())
    endfor
    call assert_equal([[3, 4], [5, 6, 7], [6, 7], [8, 9],
        \ [2, 3, 4, 5, 6, 7, 8, 9]], l:steps)
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
    call Keys('2G\hd')
    call assert_equal([2, 3, 5], s:lit())
    call Keys('1G\hd')
    call assert_equal([1, 2, 3, 5, 6], s:lit())
endfunction

function! Test_no_block_at_top_level_line() abort
    call SetLines(['a', 'b'])
    call Keys('\hd')
    call assert_false(exists('b:spotlight'))
endfunction

function! Test_adding_a_region_leaves_block_walk() abort
    call SetLines(s:js)
    call Keys('4G\hd')
    1,9SpotlightAdd
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

function! Test_block_grows_with_line_added_after_its_end() abort
    " Python blocks have no closing line, so a line opened below the last
    " one is only part of the block by indentation.
    call RequireTracking()
    call SetLines(['def f():', '    if ok:', '        a', '        b',
        \ '    return 1'])
    setlocal autoindent
    call Keys('3G\hd')
    call Keys("4Goc\<Esc>")
    call assert_equal([2, 3, 4, 5], s:lit())
    " Dedenting it again takes it back out.
    call Keys('5G<<')
    call assert_equal([2, 3, 4], s:lit())
endfunction

function! Test_manual_region_does_not_grow() abort
    call RequireTracking()
    call SetLines(['def f():', '    if ok:', '        a', '        b',
        \ '    return 1'])
    setlocal autoindent
    2,4Spotlight
    call Keys("4Goc\<Esc>")
    call assert_equal([2, 3, 4], s:lit())
endfunction

" Like a real method: chunks of code between blank lines, each usually
" starting with a comment, with blocks inside some of them.
let s:solve = [
    \ 'def solve(self):',
    \ '    """Finds a solution."""',
    \ '',
    \ '    # Keep track',
    \ '    self.num = 0',
    \ '',
    \ '    # Initialize an empty explored set',
    \ '    self.explored = set()',
    \ '',
    \ '    # Keep looping',
    \ '    while True:',
    \ '',
    \ '        # Nothing left',
    \ '        if empty():',
    \ '            raise Error()',
    \ '',
    \ '        node = pop()',
    \ '',
    \ 'other = 1',
    \ ]

function! Test_chunks_between_blank_lines_are_blocks() abort
    call SetLines(s:solve)
    call Keys('7G\hd')
    call assert_equal([7, 8], s:lit())
    " A chunk holding a block keeps all of it, blank lines included.
    call Keys('10G\hd')
    call assert_equal([10, 11, 13, 14, 15, 17], s:lit())
    " Inside the while, its own chunks.
    call Keys('17G\hd')
    call assert_equal([17], s:lit())
endfunction

function! Test_walk_chunks_and_blocks_in_order() abort
    call SetLines(s:solve)
    call Keys('1G\hd')
    let l:steps = []
    for l:i in range(9)
        call Keys('\hn')
        call add(l:steps, s:lit())
    endfor
    call assert_equal([
        \ [2], [4, 5], [7, 8],
        \ [10, 11, 13, 14, 15, 17],
        \ [11, 13, 14, 15, 17],
        \ [13, 14, 15], [14, 15], [17],
        \ [1, 2, 4, 5, 7, 8, 10, 11, 13, 14, 15, 17],
        \ ], l:steps)
endfunction

function! Test_chunk_with_nothing_inside_walks_its_neighbours() abort
    call SetLines(s:solve)
    call Keys('7G\hd')
    call assert_equal([7, 8], s:lit())
    call Keys('\hn')
    call assert_equal([10, 11, 13, 14, 15, 17], s:lit())
    call Keys('\hb\hb')
    call assert_equal([4, 5], s:lit())
endfunction
