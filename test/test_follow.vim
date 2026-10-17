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

function! Test_follow_top_level_dims_nothing_but_keeps_following() abort
    call s:require_timers()
    call SetLines(s:py)
    try
        call Keys('4G\hm')
        call cursor(7, 1)
        call s:settle()
        call assert_equal([], SpotlightMatches())
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
