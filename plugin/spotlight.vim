" plugin/spotlight.vim — dim everything outside what you're looking at
" Source:  https://github.com/arthurdaquinosilva/vim-spotlight
" License: MIT

if exists('g:loaded_spotlight') || &compatible
    finish
endif
let g:loaded_spotlight = 1

" ── Highlight group ──────────────────────────────────────────────────────────
" Defined with :highlight default so a user's customization (in colorscheme
" or vimrc) wins. Re-applied on ColorScheme since most colorschemes clear
" plugin-defined groups when they load.

function! s:set_highlight() abort
    highlight default SpotlightDim ctermfg=236 guifg=#282828
endfunction
call s:set_highlight()

augroup spotlight_highlight
    autocmd!
    autocmd ColorScheme * call s:set_highlight()
augroup END

" ── Autocommands ─────────────────────────────────────────────────────────────

augroup spotlight
    autocmd!
    autocmd BufEnter,WinEnter * call spotlight#restore()
    autocmd TextChanged,TextChangedI * call spotlight#update()
    autocmd VimLeave * silent! delmarks s e
augroup END

" ── Commands ─────────────────────────────────────────────────────────────────

command! -range Spotlight call spotlight#dim_lines(<line1>, <line2>)
command! SpotlightClear   call spotlight#clear()

" ── <Plug> mappings (always defined; safe to remap) ──────────────────────────

vnoremap <silent> <Plug>(SpotlightToggle)
    \ :<C-u>call spotlight#toggle_visual()<CR>
nnoremap <silent> <expr> <Plug>(SpotlightOperator)
    \ spotlight#maybe_clear()

" ── Default key bindings ─────────────────────────────────────────────────────
" Opt out with: let g:spotlight_no_default_mappings = 1

if get(g:, 'spotlight_no_default_mappings', 0)
    finish
endif

if !hasmapto('<Plug>(SpotlightToggle)', 'v')
    silent! vmap <unique> <leader>h <Plug>(SpotlightToggle)
endif
if !hasmapto('<Plug>(SpotlightOperator)', 'n')
    silent! nmap <unique> <leader>h <Plug>(SpotlightOperator)
endif
