scriptencoding utf-8
" plugin/spotlight.vim — dim everything outside what you're looking at
" Source:  https://github.com/arthurdaquinosilva/vim-spotlight
" License: MIT

if exists('g:loaded_spotlight') || &compatible
    finish
endif
if !has('nvim-0.5') && (has('nvim') || v:version < 802)
    echohl WarningMsg
    echomsg 'vim-spotlight: requires Vim 8.2+ or Neovim 0.5+'
    echohl None
    finish
endif
let g:loaded_spotlight = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

" ── Highlight group ──────────────────────────────────────────────────────────
" Defined with :highlight default so a colorscheme or vimrc setting wins.
" Re-applied on ColorScheme (most colorschemes clear unknown groups) and when
" 'background' flips, picking a dim color that suits a dark or light theme.
" A definition we did not make ourselves (user colors or a :hi link) is never
" touched.

let s:defaults = {
    \ 'dark':  {'cterm': '236', 'gui': '#282828'},
    \ 'light': {'cterm': '253', 'gui': '#dadada'},
    \ }
let s:applied = {}

function! s:set_highlight() abort
    let l:id = hlID('SpotlightDim')
    if l:id && synIDtrans(l:id) != l:id
        return
    endif
    let l:current = {
        \ 'cterm': synIDattr(l:id, 'fg', 'cterm'),
        \ 'gui': synIDattr(l:id, 'fg#', 'gui'),
        \ }
    let l:cleared = empty(l:current.cterm) && empty(l:current.gui)
    if !l:cleared && l:current !=? s:applied
        return
    endif
    let l:colors = s:defaults[&background ==# 'light' ? 'light' : 'dark']
    highlight clear SpotlightDim
    execute 'highlight default SpotlightDim'
        \ 'ctermfg=' . l:colors.cterm 'guifg=' . l:colors.gui
    let s:applied = copy(l:colors)
endfunction
call s:set_highlight()

" ── Autocommands ─────────────────────────────────────────────────────────────
" Kept cheap: the autoload script is only touched when a buffer or window
" actually has a spotlight, so it is not loaded at startup.

augroup spotlight
    autocmd!
    autocmd ColorScheme * call s:set_highlight()
    autocmd OptionSet background call s:set_highlight()
    autocmd BufWinEnter,WinEnter *
        \ if exists('b:spotlight') || get(w:, 'spotlight', 0)
        \ | call spotlight#sync_window()
        \ | endif
augroup END

" ── Commands ─────────────────────────────────────────────────────────────────

command! -bar -bang -range Spotlight
    \ call spotlight#command(<bang>0, <line1>, <line2>)
command! -bar -range SpotlightAdd call spotlight#add_lines(<line1>, <line2>)
command! -bar SpotlightClear call spotlight#clear()
command! -bar SpotlightToggleRegion call spotlight#toggle_region()
command! -bar SpotlightNext call spotlight#focus(1)
command! -bar SpotlightPrev call spotlight#focus(-1)
command! -bar SpotlightScopes call spotlight#scopes()

" ── <Plug> mappings (always defined; safe to remap) ──────────────────────────
" xnoremap rather than vnoremap: Select mode must keep typing over the
" selection (snippets!) instead of firing the mapping.

" Add a region (or start the spotlight when nothing is lit): the defaults.
nnoremap <silent> <expr> <Plug>(SpotlightAddOperator) spotlight#add_operator_map()
xnoremap <silent> <expr> <Plug>(SpotlightAddVisual) spotlight#visual_map(1)
nnoremap <silent> <Plug>(SpotlightClear) :<C-u>call spotlight#clear()<CR>
nnoremap <silent> <Plug>(SpotlightToggleRegion) :<C-u>call spotlight#toggle_region()<CR>
nnoremap <silent> <Plug>(SpotlightNext) :<C-u>call spotlight#focus(1)<CR>
nnoremap <silent> <Plug>(SpotlightPrev) :<C-u>call spotlight#focus(-1)<CR>
nnoremap <silent> <Plug>(SpotlightScopes) :<C-u>call spotlight#scopes()<CR>
" One region at a time, as in 1.x: the operator clears when a spotlight is
" on, Visual mode replaces it (or, for SpotlightToggle, clears it).
nnoremap <silent> <expr> <Plug>(SpotlightOperator) spotlight#operator_map()
xnoremap <silent> <expr> <Plug>(SpotlightVisual) spotlight#visual_map()
xnoremap <silent> <expr> <Plug>(SpotlightToggle) spotlight#visual_toggle_map()

" ── Default key bindings ─────────────────────────────────────────────────────
" Opt out with: let g:spotlight_no_default_mappings = 1
" Everything hangs off one key (<leader>h): the key plus a motion lights or
" adds a region, the key plus c / x / n / b clears, switches a region off or
" on, and focuses the next / previous region; d makes regions of the file's
" functions, classes and methods. Those letters are not useful
" as motions here. Longer mappings that merely start with the same key (e.g.
" vim-gitgutter's <leader>hp) are fine: <leader>h{motion} resolves as soon as
" the motion is typed. Only an existing mapping for the exact key is left
" alone.

function! s:map_default(mode, key, plugs) abort
    for l:plug in a:plugs
        if hasmapto(l:plug, a:mode)
            return
        endif
    endfor
    if empty(a:key) || !empty(maparg(a:key, a:mode))
        return
    endif
    execute a:mode . 'map <unique> ' . a:key . ' ' . a:plugs[0]
endfunction

if !get(g:, 'spotlight_no_default_mappings', 0)
    let s:key = get(g:, 'spotlight_mapping', '<leader>h')
    call s:map_default('n', s:key, ['<Plug>(SpotlightAddOperator)',
        \ '<Plug>(SpotlightOperator)'])
    call s:map_default('x', s:key, ['<Plug>(SpotlightAddVisual)',
        \ '<Plug>(SpotlightVisual)', '<Plug>(SpotlightToggle)'])
    for [s:name, s:letter, s:plug] in [
        \ ['clear', 'c', 'SpotlightClear'],
        \ ['toggle', 'x', 'SpotlightToggleRegion'],
        \ ['next', 'n', 'SpotlightNext'],
        \ ['prev', 'b', 'SpotlightPrev'],
        \ ['scopes', 'd', 'SpotlightScopes'],
        \ ]
        call s:map_default('n', get(g:, 'spotlight_' . s:name . '_mapping',
            \ empty(s:key) ? '' : s:key . s:letter), ['<Plug>(' . s:plug . ')'])
    endfor
    unlet s:key s:name s:letter s:plug
endif

let &cpoptions = s:save_cpo
unlet s:save_cpo
