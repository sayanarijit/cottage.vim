" ============================================================================
" Plugin:   cottage.vim
" Summary:  Transparent decryption and encryption of cottage secrets in Vim / Neovim
" Author:   sayanarijit
" License:  MIT
" ============================================================================

let s:tracked_files = {}
let s:in_flight = {}

" ----------------------------------------------------------------------------
" Logging / Messages
" ----------------------------------------------------------------------------
function! cottage#msg(text) abort
  echohl Directory
  echomsg 'Cottage: ' . a:text
  echohl None
endfunction

function! cottage#warn(text) abort
  echohl WarningMsg
  echomsg 'Cottage: ' . a:text
  echohl None
endfunction

function! cottage#error(text) abort
  echohl ErrorMsg
  echomsg 'Cottage: ' . a:text
  echohl None
endfunction

" ----------------------------------------------------------------------------
" Path Helpers
" ----------------------------------------------------------------------------
function! s:normalize_path(path) abort
  let l:p = fnamemodify(a:path, ':p')
  let l:p = simplify(l:p)
  if has('win32')
    let l:p = substitute(l:p, '\\', '/', 'g')
    let l:p = tolower(l:p)
  endif
  return l:p
endfunction

function! s:is_encrypted_file(path) abort
  return a:path =~? '\.cott\.age$'
endfunction

function! s:get_decrypted_path(enc_path) abort
  return substitute(a:enc_path, '\c\.cott\.age$', '', '')
endfunction

function! s:get_encrypted_path(dec_path) abort
  return a:dec_path . '.cott.age'
endfunction

" ----------------------------------------------------------------------------
" Command Execution
" ----------------------------------------------------------------------------
function! s:run_command(cmd, ...) abort
  let l:cwd = a:0 > 0 && !empty(a:1) ? a:1 : ''
  let l:prev_cwd = ''
  if !empty(l:cwd) && isdirectory(l:cwd)
    let l:prev_cwd = getcwd()
    execute 'lcd ' . fnameescape(l:cwd)
  endif
  try
    let l:out = system(a:cmd)
    let l:code = v:shell_error
    return {'code': l:code, 'output': l:out}
  finally
    if !empty(l:prev_cwd)
      execute 'lcd ' . fnameescape(l:prev_cwd)
    endif
  endtry
endfunction

" ----------------------------------------------------------------------------
" Executable Resolution & Auto-Installer
" ----------------------------------------------------------------------------
function! cottage#get_search_directories() abort
  let l:dirs = []
  let l:home = expand('~')
  if !has('win32') && !empty(l:home)
    call add(l:dirs, l:home . '/.cargo/bin')
    call add(l:dirs, l:home . '/.local/bin')
    call add(l:dirs, l:home . '/.npm-global/bin')
    call add(l:dirs, l:home . '/.config/yarn/global/node_modules/.bin')
    call add(l:dirs, l:home . '/.yarn/bin')
    call add(l:dirs, l:home . '/.local/share/pnpm')
    call add(l:dirs, l:home . '/bin')
  elseif has('win32') && !empty(l:home)
    call add(l:dirs, l:home . '\.cargo\bin')
    call add(l:dirs, l:home . '\AppData\Local\Programs\Python\Python3*\Scripts')
    call add(l:dirs, l:home . '\AppData\Roaming\npm')
    call add(l:dirs, l:home . '\AppData\Local\pnpm')
    call add(l:dirs, l:home . '\bin')
  endif
  return l:dirs
endfunction

function! cottage#find_ctg() abort
  if exists('g:cottage_bin') && !empty(g:cottage_bin)
    if executable(g:cottage_bin)
      return g:cottage_bin
    endif
  endif

  if executable('ctg')
    return 'ctg'
  endif

  let l:names = has('win32') ? ['ctg.exe', 'ctg.cmd', 'ctg.bat', 'ctg'] : ['ctg']
  for l:dir in cottage#get_search_directories()
    for l:name in l:names
      let l:candidate = l:dir . (has('win32') ? '\' : '/') . l:name
      let l:globbed = glob(l:candidate, 1, 1)
      if !empty(l:globbed)
        for l:match in l:globbed
          if filereadable(l:match) && executable(l:match)
            let l:pdir = fnamemodify(l:match, ':h')
            let $PATH = l:pdir . (has('win32') ? ';' : ':') . $PATH
            return l:match
          endif
        endfor
      elseif filereadable(l:candidate) && executable(l:candidate)
        let $PATH = l:dir . (has('win32') ? ';' : ':') . $PATH
        return l:candidate
      endif
    endfor
  endfor

  return ''
endfunction

function! cottage#detect_best_installer() abort
  " 1. cargo binstall
  if executable('cargo')
    call system('cargo binstall --help')
    if v:shell_error == 0
      return {
            \ 'label': 'cargo binstall (crates.io binary)',
            \ 'cmd': 'cargo binstall --locked cottage -y'
            \ }
    endif
  endif

  " 2. cargo install
  if executable('cargo')
    return {
          \ 'label': 'cargo install (crates.io source)',
          \ 'cmd': 'cargo install --locked cottage'
          \ }
  endif

  " 3. uv tool install
  if executable('uv')
    return {
          \ 'label': 'uv tool install (PyPI)',
          \ 'cmd': 'uv tool install --force cottage'
          \ }
  endif

  " 4. pipx install
  if executable('pipx')
    call system('pipx --version')
    if v:shell_error == 0
      return {
            \ 'label': 'pipx install (PyPI)',
            \ 'cmd': 'pipx install --force cottage'
            \ }
    endif
  endif

  " 5. python3 -m pip install --user
  let l:py = executable('python3') ? 'python3' : (executable('python') ? 'python' : '')
  if !empty(l:py)
    call system(l:py . ' -m pip --version')
    if v:shell_error == 0
      return {
            \ 'label': l:py . ' -m pip (PyPI user install)',
            \ 'cmd': l:py . ' -m pip install --user cottage'
            \ }
    endif
  endif

  " 6. pnpm add -g
  if executable('pnpm')
    return {
          \ 'label': 'pnpm global add (npm registry)',
          \ 'cmd': 'pnpm add -g @sayanarijit/cottage'
          \ }
  endif

  " 7. yarn global add
  if executable('yarn')
    return {
          \ 'label': 'yarn global add (npm registry)',
          \ 'cmd': 'yarn global add @sayanarijit/cottage'
          \ }
  endif

  " 8. npm install -g
  if executable('npm')
    return {
          \ 'label': 'npm global install (npm registry)',
          \ 'cmd': 'npm install -g @sayanarijit/cottage'
          \ }
  endif

  return {}
endfunction

function! cottage#ensure_installed() abort
  let l:bin = cottage#find_ctg()
  if !empty(l:bin)
    return 1
  endif

  if !get(g:, 'cottage_auto_install', 1)
    return 0
  endif

  return cottage#cmd_install()
endfunction

function! cottage#cmd_install() abort
  let l:installer = cottage#detect_best_installer()
  if empty(l:installer)
    call cottage#error("No supported installer found. Expected one of: cargo, uv, pipx, python3, pnpm, yarn, or npm.")
    return 0
  endif

  call cottage#msg("Installing cottage via " . l:installer.label . "...")
  redraw

  let l:res = s:run_command(l:installer.cmd, getcwd())
  if l:res.code != 0
    call cottage#error("Installation failed: " . trim(l:res.output))
    return 0
  endif

  let l:bin = cottage#find_ctg()
  if empty(l:bin)
    call cottage#error("Installed cottage, but ctg is not yet visible on PATH. Restart your editor or check your PATH.")
    return 0
  endif

  call cottage#msg("Installed cottage successfully via " . l:installer.label . ".")
  return 1
endfunction

" ----------------------------------------------------------------------------
" Workspace Management
" ----------------------------------------------------------------------------
function! cottage#get_root(dir) abort
  let l:current = fnamemodify(a:dir, ':p')
  let l:current = simplify(l:current)

  " Walk upward to find .cottage
  let l:check = l:current
  while 1
    if isdirectory(l:check . '/.cottage')
      return l:check
    endif
    let l:parent = fnamemodify(l:check, ':h')
    if l:parent ==# l:check
      break
    endif
    let l:check = l:parent
  endwhile

  " Walk upward to find .git
  let l:check = l:current
  while 1
    if isdirectory(l:check . '/.git') || filereadable(l:check . '/.git')
      return l:check
    endif
    let l:parent = fnamemodify(l:check, ':h')
    if l:parent ==# l:check
      break
    endif
    let l:check = l:parent
  endwhile

  return isdirectory(a:dir) ? a:dir : getcwd()
endfunction

function! cottage#ensure_initialized(root) abort
  if isdirectory(a:root . '/.cottage')
    return 1
  endif

  let l:ctg_bin = cottage#find_ctg()
  if empty(l:ctg_bin)
    return 0
  endif

  call cottage#msg("Initializing cottage in " . a:root . "...")
  let l:res = s:run_command(shellescape(l:ctg_bin) . ' init', a:root)
  if l:res.code != 0
    call cottage#error("Cottage initialization failed: " . trim(l:res.output))
    return 0
  endif

  return 1
endfunction

" ----------------------------------------------------------------------------
" Decrypted Buffer Configuration
" ----------------------------------------------------------------------------
function! s:setup_decrypted_buffer(dec_path, enc_path) abort
  let b:cottage_tracked = 1
  let b:cottage_decrypted_path = a:dec_path
  let b:cottage_encrypted_path = a:enc_path

  if get(g:, 'cottage_disable_swapfile', 1)
    setlocal noswapfile
  endif

  if get(g:, 'cottage_disable_backup', 1)
    setlocal nobackup
    setlocal nowritebackup
  endif

  if get(g:, 'cottage_disable_undofile', 0)
    setlocal noundofile
  endif

  let l:norm_dec = s:normalize_path(a:dec_path)
  let s:tracked_files[l:norm_dec] = {
        \ 'decrypted_path': a:dec_path,
        \ 'encrypted_path': a:enc_path,
        \ 'bufnr': bufnr('%')
        \ }
endfunction

function! s:read_raw_buffer() abort
  let l:file = expand('<afile>')
  if filereadable(l:file)
    execute 'silent! 0read ' . fnameescape(l:file)
    silent! $delete _
    setlocal nomodified
  endif
endfunction

" ----------------------------------------------------------------------------
" Autocommand Handlers
" ----------------------------------------------------------------------------
function! cottage#on_buf_read_cmd() abort
  if !get(g:, 'cottage_enabled', 1)
    call s:read_raw_buffer()
    return
  endif

  let l:enc_path = fnamemodify(expand('<afile>'), ':p')
  let l:enc_buf = str2nr(expand('<abuf>'))

  if empty(l:enc_path) || !s:is_encrypted_file(l:enc_path)
    return
  endif

  let l:norm_enc = s:normalize_path(l:enc_path)
  if has_key(s:in_flight, l:norm_enc)
    return
  endif
  let s:in_flight[l:norm_enc] = 1

  try
    if !cottage#ensure_installed()
      call cottage#error("ctg binary not found. Run :CottageInstall to install it.")
      call s:read_raw_buffer()
      return
    endif

    let l:dec_path = s:get_decrypted_path(l:enc_path)
    let l:norm_dec = s:normalize_path(l:dec_path)
    let l:ctg_bin = cottage#find_ctg()
    let l:file_dir = fnamemodify(l:enc_path, ':h')

    " Check if decrypted buffer is already open
    let l:existing_buf = bufnr(fnameescape(l:dec_path))
    if l:existing_buf != -1 && l:existing_buf != l:enc_buf && bufloaded(l:existing_buf)
      execute 'buffer ' . l:existing_buf
      if l:enc_buf != bufnr('%') && bufexists(l:enc_buf)
        execute 'silent! bwipeout! ' . l:enc_buf
      endif
      return
    endif

    " Run ctg decrypt
    let l:res = s:run_command(shellescape(l:ctg_bin) . ' decrypt ' . shellescape(l:enc_path), l:file_dir)
    if l:res.code != 0
      call cottage#error("Failed to decrypt " . fnamemodify(l:enc_path, ':t') . ": " . trim(l:res.output))
      call s:read_raw_buffer()
      return
    endif

    " Transform current buffer into the decrypted file buffer
    execute 'file ' . fnameescape(l:dec_path)
    setlocal buftype=
    silent %delete _
    execute 'silent 0read ' . fnameescape(l:dec_path)
    silent $delete _
    setlocal nomodified

    " Configure buffer settings and tracking
    call s:setup_decrypted_buffer(l:dec_path, l:enc_path)

    " Detect filetype for the decrypted file
    filetype detect

    if !get(g:, 'cottage_quiet', 0)
      call cottage#msg("Decrypted " . fnamemodify(l:enc_path, ':t'))
    endif
  finally
    unlet! s:in_flight[l:norm_enc]
  endtry
endfunction

function! cottage#on_buf_write_post() abort
  if !get(g:, 'cottage_enabled', 1) || !get(g:, 'cottage_sync_on_save', 1)
    return
  endif

  let l:file = fnamemodify(expand('<afile>'), ':p')
  let l:norm = s:normalize_path(l:file)

  if !has_key(s:tracked_files, l:norm) && !get(b:, 'cottage_tracked', 0)
    return
  endif

  if has_key(s:in_flight, l:norm)
    return
  endif
  let s:in_flight[l:norm] = 1

  try
    let l:ctg_bin = cottage#find_ctg()
    if empty(l:ctg_bin)
      return
    endif

    let l:file_dir = fnamemodify(l:file, ':h')
    let l:res = s:run_command(shellescape(l:ctg_bin) . ' encrypt ' . shellescape(l:file), l:file_dir)
    if l:res.code != 0
      call cottage#error("Failed to sync encryption for " . fnamemodify(l:file, ':t') . ": " . trim(l:res.output))
    elseif !get(g:, 'cottage_quiet', 0)
      call cottage#msg("Synced encryption for " . fnamemodify(l:file, ':t'))
    endif
  finally
    unlet! s:in_flight[l:norm]
  endtry
endfunction

function! s:finalize_tracked_file(file, bufnr_val) abort
  let l:norm = s:normalize_path(a:file)
  if has_key(s:in_flight, l:norm)
    return
  endif
  let s:in_flight[l:norm] = 1

  try
    if !filereadable(a:file)
      unlet! s:tracked_files[l:norm]
      return
    endif

    let l:ctg_bin = cottage#find_ctg()
    if empty(l:ctg_bin)
      return
    endif

    let l:bnr = str2nr(a:bufnr_val)
    if l:bnr > 0 && bufexists(l:bnr) && getbufvar(l:bnr, '&modified')
      execute 'noautocmd silent! ' . l:bnr . 'bufdo! write'
    endif

    let l:file_dir = fnamemodify(a:file, ':h')
    let l:res = s:run_command(shellescape(l:ctg_bin) . ' encrypt ' . shellescape(a:file) . ' --clean', l:file_dir)
    if l:res.code != 0
      call cottage#error("Failed to encrypt and clean " . fnamemodify(a:file, ':t') . ": " . trim(l:res.output))
    elseif !get(g:, 'cottage_quiet', 0)
      call cottage#msg("Encrypted & cleaned " . fnamemodify(a:file, ':t'))
    endif

    unlet! s:tracked_files[l:norm]
  finally
    unlet! s:in_flight[l:norm]
  endtry
endfunction

function! cottage#on_buf_unload() abort
  if !get(g:, 'cottage_enabled', 1) || !get(g:, 'cottage_clean_on_close', 1)
    return
  endif

  let l:file = fnamemodify(expand('<afile>'), ':p')
  let l:norm = s:normalize_path(l:file)

  if !has_key(s:tracked_files, l:norm) && !get(b:, 'cottage_tracked', 0)
    return
  endif

  call s:finalize_tracked_file(l:file, expand('<abuf>'))
endfunction

function! cottage#on_buf_leave() abort
  if !get(g:, 'cottage_enabled', 1) || !get(g:, 'cottage_clean_on_leave', 0)
    return
  endif

  let l:file = fnamemodify(expand('<afile>'), ':p')
  let l:norm = s:normalize_path(l:file)

  if !has_key(s:tracked_files, l:norm) && !get(b:, 'cottage_tracked', 0)
    return
  endif

  let l:bnr = bufnr(fnameescape(l:file))
  if l:bnr != -1 && exists('*win_findbuf')
    let l:wins = win_findbuf(l:bnr)
    if len(l:wins) > 1
      return
    endif
  endif

  call s:finalize_tracked_file(l:file, expand('<abuf>'))
endfunction

function! cottage#on_vim_leave() abort
  if !get(g:, 'cottage_enabled', 1) || !get(g:, 'cottage_clean_on_exit', 1)
    return
  endif

  let l:ctg_bin = cottage#find_ctg()
  if empty(l:ctg_bin)
    return
  endif

  for [l:norm, l:meta] in items(s:tracked_files)
    let l:file = l:meta.decrypted_path
    if !filereadable(l:file)
      continue
    endif
    let l:bnr = get(l:meta, 'bufnr', -1)
    if l:bnr > 0 && bufexists(l:bnr) && getbufvar(l:bnr, '&modified')
      execute 'noautocmd silent! ' . l:bnr . 'bufdo! write'
    endif
    let l:file_dir = fnamemodify(l:file, ':h')
    call s:run_command(shellescape(l:ctg_bin) . ' encrypt ' . shellescape(l:file) . ' --clean', l:file_dir)
  endfor

  let s:tracked_files = {}
endfunction

" ----------------------------------------------------------------------------
" Output Viewer Window
" ----------------------------------------------------------------------------
function! s:display_output(title, content, ...) abort
  let l:ft = a:0 > 0 ? a:1 : ''
  if empty(trim(a:content))
    call cottage#msg(a:title . ': No output.')
    return
  endif

  botright new
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nowrap
  let &l:filetype = l:ft
  let l:lines = split(a:content, "\n")
  call setline(1, l:lines)
  setlocal nomodifiable
  nnoremap <buffer> <silent> q :close<CR>
endfunction

" ----------------------------------------------------------------------------
" Command Implementations
" ----------------------------------------------------------------------------
function! cottage#cmd_encrypt(...) abort
  let l:file = a:0 > 0 && !empty(a:1) ? fnamemodify(a:1, ':p') : fnamemodify(expand('%:p'), ':p')
  if empty(l:file)
    call cottage#error("No file specified to encrypt.")
    return
  endif

  if s:is_encrypted_file(l:file)
    call cottage#warn("File is already a cottage encrypted file: " . fnamemodify(l:file, ':t'))
    return
  endif

  if !filereadable(l:file)
    call cottage#error("File not found: " . l:file)
    return
  endif

  if !cottage#ensure_installed()
    call cottage#error("ctg binary not found. Run :CottageInstall to install it.")
    return
  endif

  let l:ctg_bin = cottage#find_ctg()
  let l:file_dir = fnamemodify(l:file, ':h')
  let l:root = cottage#get_root(l:file_dir)

  if get(g:, 'cottage_auto_init', 1)
    call cottage#ensure_initialized(l:root)
  endif

  let l:bnr = bufnr(fnameescape(l:file))
  if l:bnr != -1 && bufexists(l:bnr) && getbufvar(l:bnr, '&modified')
    execute 'noautocmd silent! ' . l:bnr . 'bufdo! write'
  endif

  let l:res = s:run_command(shellescape(l:ctg_bin) . ' encrypt ' . shellescape(l:file) . ' --clean', l:root)
  if l:res.code != 0
    call cottage#error("Encryption failed: " . trim(l:res.output))
    return
  endif

  let l:norm = s:normalize_path(l:file)
  unlet! s:tracked_files[l:norm]

  let l:enc_file = s:get_encrypted_path(l:file)
  if l:bnr != -1 && bufexists(l:bnr)
    execute 'silent! bwipeout! ' . l:bnr
  endif

  execute 'edit ' . fnameescape(l:enc_file)

  call cottage#msg("Encrypted " . fnamemodify(l:file, ':t') . " -> " . fnamemodify(l:enc_file, ':t'))
endfunction

function! cottage#cmd_decrypt(...) abort
  let l:file = a:0 > 0 && !empty(a:1) ? fnamemodify(a:1, ':p') : fnamemodify(expand('%:p'), ':p')
  if empty(l:file)
    call cottage#error("No file specified to decrypt.")
    return
  endif

  if !s:is_encrypted_file(l:file)
    call cottage#error("File is not a .cott.age encrypted file: " . fnamemodify(l:file, ':t'))
    return
  endif

  if !filereadable(l:file)
    call cottage#error("File not found: " . l:file)
    return
  endif

  execute 'edit ' . fnameescape(l:file)
endfunction

function! cottage#cmd_init(...) abort
  let l:dir = a:0 > 0 && !empty(a:1) ? fnamemodify(a:1, ':p') : cottage#get_root(getcwd())
  if !cottage#ensure_installed()
    call cottage#error("ctg binary not found. Run :CottageInstall to install it.")
    return
  endif

  let l:ctg_bin = cottage#find_ctg()
  let l:res = s:run_command(shellescape(l:ctg_bin) . ' init', l:dir)
  if l:res.code != 0
    call cottage#error("ctg init failed: " . trim(l:res.output))
  else
    call cottage#msg("Initialized cottage in " . l:dir)
  endif
endfunction

function! cottage#cmd_clean() abort
  if !cottage#ensure_installed()
    call cottage#error("ctg binary not found.")
    return
  endif

  let l:ctg_bin = cottage#find_ctg()
  let l:root = cottage#get_root(getcwd())
  let l:res = s:run_command(shellescape(l:ctg_bin) . ' clean -qqq', l:root)
  let s:tracked_files = {}
  if l:res.code != 0
    call cottage#error("ctg clean failed: " . trim(l:res.output))
  else
    call cottage#msg("Cleaned all decrypted secrets and identity files.")
  endif
endfunction

function! cottage#cmd_status() abort
  if !cottage#ensure_installed()
    call cottage#error("ctg binary not found.")
    return
  endif

  let l:ctg_bin = cottage#find_ctg()
  let l:root = cottage#get_root(getcwd())
  let l:res = s:run_command(shellescape(l:ctg_bin) . ' status', l:root)
  if l:res.code != 0
    call cottage#error("ctg status failed: " . trim(l:res.output))
  else
    call s:display_output("Cottage Status", l:res.output)
  endif
endfunction

function! cottage#cmd_diff(...) abort
  if !cottage#ensure_installed()
    call cottage#error("ctg binary not found.")
    return
  endif

  let l:ctg_bin = cottage#find_ctg()
  let l:root = cottage#get_root(getcwd())
  let l:target = a:0 > 0 && !empty(a:1) ? ' ' . shellescape(a:1) : ''
  let l:res = s:run_command(shellescape(l:ctg_bin) . ' diff' . l:target, l:root)
  if l:res.code != 0
    call cottage#error("ctg diff failed: " . trim(l:res.output))
  else
    call s:display_output("Cottage Diff", l:res.output, "diff")
  endif
endfunction

function! cottage#cmd_pull() abort
  if !cottage#ensure_installed()
    call cottage#error("ctg binary not found.")
    return
  endif

  let l:ctg_bin = cottage#find_ctg()
  let l:root = cottage#get_root(getcwd())
  let l:res = s:run_command(shellescape(l:ctg_bin) . ' pull', l:root)
  if l:res.code != 0
    call cottage#error("ctg pull failed: " . trim(l:res.output))
  else
    call cottage#msg("Pulled secrets successfully: " . trim(l:res.output))
  endif
endfunction

function! cottage#cmd_push() abort
  if !cottage#ensure_installed()
    call cottage#error("ctg binary not found.")
    return
  endif

  let l:ctg_bin = cottage#find_ctg()
  let l:root = cottage#get_root(getcwd())
  let l:res = s:run_command(shellescape(l:ctg_bin) . ' push', l:root)
  if l:res.code != 0
    call cottage#error("ctg push failed: " . trim(l:res.output))
  else
    call cottage#msg("Pushed secrets successfully: " . trim(l:res.output))
  endif
endfunction

" ----------------------------------------------------------------------------
" Command Completion Helpers
" ----------------------------------------------------------------------------
function! cottage#complete_encrypted(ArgLead, CmdLine, CursorPos) abort
  let l:pattern = empty(a:ArgLead) ? '*' : a:ArgLead . '*'
  let l:files = glob(l:pattern, 0, 1)
  let l:result = []
  for l:f in l:files
    if l:f =~# '\.cott\.age$' || isdirectory(l:f)
      call add(l:result, isdirectory(l:f) ? l:f . '/' : l:f)
    endif
  endfor
  return l:result
endfunction

" ----------------------------------------------------------------------------
" Introspection for Testing
" ----------------------------------------------------------------------------
function! cottage#get_tracked_files() abort
  return deepcopy(s:tracked_files)
endfunction
