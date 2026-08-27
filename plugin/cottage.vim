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

if !exists('g:cottage_sync_on_save')
  let g:cottage_sync_on_save = 1
endif

if !exists('g:cottage_clean_on_close')
  let g:cottage_clean_on_close = 1
endif

if !exists('g:cottage_clean_on_exit')
  let g:cottage_clean_on_exit = 1
endif

if !exists('g:cottage_clean_on_leave')
  let g:cottage_clean_on_leave = 0
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
  let g:cottage_disable_undofile = 0
endif

if !exists('g:cottage_quiet')
  let g:cottage_quiet = 0
endif

" ----------------------------------------------------------------------------
" User Commands
" ----------------------------------------------------------------------------
command! -nargs=? -complete=file CottageEncrypt call cottage#cmd_encrypt(<f-args>)
command! -nargs=? -complete=customlist,cottage#complete_encrypted CottageDecrypt call cottage#cmd_decrypt(<f-args>)
command! -nargs=0 CottageInstall call cottage#cmd_install()
command! -nargs=? -complete=dir CottageInit call cottage#cmd_init(<f-args>)
command! -nargs=0 CottageClean call cottage#cmd_clean()
command! -nargs=0 CottageStatus call cottage#cmd_status()
command! -nargs=? -complete=file CottageDiff call cottage#cmd_diff(<f-args>)
command! -nargs=0 CottagePull call cottage#cmd_pull()
command! -nargs=0 CottagePush call cottage#cmd_push()

" ----------------------------------------------------------------------------
" Autocommands
" ----------------------------------------------------------------------------
augroup cottage
  autocmd!
  autocmd BufReadCmd *.cott.age call cottage#on_buf_read_cmd()
  autocmd BufWritePost * call cottage#on_buf_write_post()
  autocmd BufUnload * call cottage#on_buf_unload()
  autocmd BufLeave * call cottage#on_buf_leave()
  autocmd VimLeavePre * call cottage#on_vim_leave()
augroup END
