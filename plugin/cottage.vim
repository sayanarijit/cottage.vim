" ============================================================================
" Plugin:   cottage.vim
" Summary:  Transparent decryption and encryption of cottage secrets in Vim / Neovim
" Author:   sayanarijit
" License:  MIT
" ============================================================================

if exists('g:loaded_cottage') || &compatible
  finish
endif
let g:loaded_cottage = 1

" ----------------------------------------------------------------------------
" Default Configurations
" ----------------------------------------------------------------------------
if !exists('g:cottage_enabled')
  let g:cottage_enabled = 1
endif

if !exists('g:cottage_auto_install')
  let g:cottage_auto_install = 1
endif

if !exists('g:cottage_bin')
  let g:cottage_bin = ''
endif

if !exists('g:cottage_auto_init')
  let g:cottage_auto_init = 1
endif

if !exists('g:cottage_disable_swapfile')
  let g:cottage_disable_swapfile = 1
endif

if !exists('g:cottage_disable_backup')
  let g:cottage_disable_backup = 1
endif

if !exists('g:cottage_disable_undofile')
  let g:cottage_disable_undofile = 1
endif

if !exists('g:cottage_quiet')
  let g:cottage_quiet = 0
endif

" ----------------------------------------------------------------------------
" User Commands
" ----------------------------------------------------------------------------
command! -nargs=? -complete=file CottageEncrypt call cottage#cmd_encrypt(<f-args>)

" ----------------------------------------------------------------------------
" Autocommands
" ----------------------------------------------------------------------------
augroup cottage
  autocmd!
  autocmd BufReadCmd *.cott.age call cottage#on_buf_read_cmd()
  autocmd BufNewFile * call cottage#on_buf_new_file()
augroup END
