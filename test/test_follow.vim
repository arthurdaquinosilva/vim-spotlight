scriptencoding utf-8
" <leader>hm: follow mode, lighting the block under the cursor as it moves.

let s:py = [
    \ 'class Shop:',
    \ '    def save(self):',
    \ '        if ok:',
    \ '            log()',
    \ '        return 1',
    \ '',
    \ 'top = 1',
    \ ]

function! s:lit() abort
    return filter(range(1, line('$')),
        \ '!empty(Mask(v:val)) && Mask(v:val) !~# "^_*$"')
endfunction

" Let the follow timer notice the cursor (it ticks every 100ms).
function! s:settle() abort
    sleep 250m
endfunction

function! s:require_timers() abort
    if !exists('*timer_start')
        throw 'Skipped: needs +timers'
    endif
endfunction

function! Test_follow_lights_block_under_cursor() abort
    call s:require_timers()
    call SetLines(s:py)
    try
        call Keys('4G\hm')
        call assert_equal([3, 4], s:lit())
        call cursor(5, 1)
        call s:settle()
        call assert_equal([2, 3, 4, 5], s:lit())
        call cursor(1, 1)
        call s:settle()
        call assert_equal([1, 2, 3, 4, 5], s:lit())
    finally
        SpotlightClear
    endtry
endfunction

function! Test_follow_top_level_lights_chunk_and_keeps_following() abort
    call s:require_timers()
    call SetLines(s:py + ['', 'x = 2', 'y = 3'])
    try
        call Keys('4G\hm')
        " Top-level code: the chunk between blank lines.
        call cursor(9, 1)
        call s:settle()
        call assert_equal([9, 10], s:lit())
        call cursor(4, 1)
        call s:settle()
        call assert_equal([3, 4], s:lit())
    finally
        SpotlightClear
    endtry
endfunction

function! Test_follow_off_with_same_key_or_clear() abort
    call s:require_timers()
    call SetLines(s:py)
    call Keys('4G\hm')
    call Keys('\hm')
    call assert_false(exists('b:spotlight'))
    call cursor(2, 1)
    call s:settle()
    call assert_false(exists('b:spotlight'))

    call Keys('4G\hm')
    call Keys('\hc')
    call cursor(2, 1)
    call s:settle()
    call assert_false(exists('b:spotlight'))
endfunction

function! Test_follow_is_per_buffer() abort
    call s:require_timers()
    call SetLines(s:py)
    let l:buf = bufnr('%')
    try
        call Keys('4G\hm')
        enew
        call setline(1, ['def f():', '    x'])
        call cursor(2, 1)
        call s:settle()
        call assert_false(exists('b:spotlight'))
    finally
        execute 'buffer' l:buf
        SpotlightClear
    endtry
endfunction

function! Test_follow_key_is_mapped() abort
    call assert_equal('<Plug>(SpotlightFollow)', maparg('<leader>hm', 'n'))
endfunction

let s:two = [
    \ 'class Shop:',
    \ '    def save(self, xs):',
    \ '        if not self.ok:',
    \ '            log()',
    \ '        for x in xs:',
    \ '            use(x)',
    \ '',
    \ '    def load(self, path):',
    \ '        with open(path) as f:',
    \ '            data = f.read()',
    \ '        if data:',
    \ '            return parse(data)',
    \ ]

function! Test_follow_walks_blocks_inside_with_n_and_b() abort
    call s:require_timers()
    call SetLines(s:two)
    try
        call Keys('2G\hm')
        call assert_equal([2, 3, 4, 5, 6], s:lit())
        call Keys('\hn')
        call s:settle()
        call assert_equal([3, 4], s:lit())
        call Keys('\hn')
        call s:settle()
        call assert_equal([5, 6], s:lit())
        call Keys('\hn')
        call s:settle()
        call assert_equal([2, 3, 4, 5, 6], s:lit())
        call Keys('\hb')
        call s:settle()
        call assert_equal([5, 6], s:lit())
    finally
        SpotlightClear
    endtry
endfunction

function! Test_follow_search_jump_then_walk_there() abort
    call s:require_timers()
    call SetLines(s:two)
    try
        call Keys('3G\hm')
        " Jump to the other method, like / does: follow lights it...
        call Keys("/def load\<CR>")
        call s:settle()
        call assert_equal([8, 9, 10, 11, 12], s:lit())
        " ... and n walks the blocks inside it.
        call Keys('\hn')
        call s:settle()
        call assert_equal([9, 10], s:lit())
        call Keys('\hn')
        call s:settle()
        call assert_equal([11, 12], s:lit())
        " Moving by hand goes back to following the cursor.
        call cursor(4, 1)
        call s:settle()
        call assert_equal([3, 4], s:lit())
    finally
        SpotlightClear
    endtry
endfunction
