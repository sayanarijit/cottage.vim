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

function! s:find_buffer_by_path(path) abort
  let l:norm_target = s:normalize_path(a:path)
  for l:b in range(1, bufnr('$'))
    if bufexists(l:b)
      let l:bname = bufname(l:b)
      if !empty(l:bname) && s:normalize_path(fnamemodify(l:bname, ':p')) ==# l:norm_target
        return l:b
      endif
    endif
  endfor
  return -1
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
" Secrets are only ever decrypted in memory (`ctg cat`) and re-encrypted from
" memory (`ctg tee` with stdin). Plaintext never touches the disk.
function! s:setup_decrypted_buffer(dec_path, enc_path) abort
  let b:cottage_tracked = 1
  let b:cottage_decrypted_path = a:dec_path
  let b:cottage_encrypted_path = a:enc_path

  setlocal buftype=acwrite

  if get(g:, 'cottage_disable_swapfile', 1)
    setlocal noswapfile
  endif

  if get(g:, 'cottage_disable_backup', 1)
    setlocal nobackup
    setlocal nowritebackup
  endif

  if get(g:, 'cottage_disable_undofile', 1)
    setlocal noundofile
  endif

  let l:norm_dec = s:normalize_path(a:dec_path)
  let s:tracked_files[l:norm_dec] = {
        \ 'decrypted_path': a:dec_path,
        \ 'encrypted_path': a:enc_path,
        \ 'bufnr': bufnr('%')
        \ }

  augroup cottage_buffer
    autocmd! * <buffer>
    autocmd BufWriteCmd <buffer> call cottage#on_buf_write_cmd()
    autocmd BufWipeout <buffer> call s:untrack(expand('<afile>:p'))
  augroup END
endfunction

function! s:untrack(file) abort
  unlet! s:tracked_files[s:normalize_path(a:file)]
endfunction

function! s:read_raw_buffer() abort
  let l:file = expand('<afile>')
  if filereadable(l:file)
    execute 'silent! 0read ' . fnameescape(l:file)
    silent! $delete _
    setlocal nomodified
  endif
endfunction

" Decrypt enc_path into the current buffer, in memory only.
function! s:load_decrypted(enc_path, dec_path) abort
  let l:ctg_bin = cottage#find_ctg()
  let l:res = s:run_command(shellescape(l:ctg_bin) . ' cat -- ' . shellescape(a:enc_path), fnamemodify(a:enc_path, ':h'))
  if l:res.code != 0
    call cottage#error("Failed to decrypt " . fnamemodify(a:enc_path, ':t') . ": " . trim(l:res.output))
    return 0
  endif

  let l:lines = split(l:res.output, "\n", 1)
  if len(l:lines) > 1 && l:lines[-1] ==# ''
    call remove(l:lines, -1)
  endif

  setlocal buftype=acwrite
  setlocal modifiable
  silent %delete _
  call setline(1, l:lines)
  setlocal nomodified
  call s:setup_decrypted_buffer(a:dec_path, a:enc_path)
  filetype detect
  return 1
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
      call cottage#error("ctg binary not found. Install it manually or set g:cottage_auto_install = 1.")
      call s:read_raw_buffer()
      return
    endif

    let l:dec_path = s:get_decrypted_path(l:enc_path)

    " Reuse an already open decrypted buffer if there is one
    let l:existing_buf = s:find_buffer_by_path(l:dec_path)
    if l:existing_buf != -1 && l:existing_buf != l:enc_buf
      execute 'buffer ' . l:existing_buf
      if l:enc_buf != bufnr('%') && bufexists(l:enc_buf)
        execute 'silent! bwipeout! ' . l:enc_buf
      endif
    elseif l:existing_buf == -1
      execute 'file ' . fnameescape(l:dec_path)
    endif

    if !s:load_decrypted(l:enc_path, l:dec_path)
      call s:read_raw_buffer()
      return
    endif

    if !get(g:, 'cottage_quiet', 0)
      call cottage#msg("Decrypted " . fnamemodify(l:enc_path, ':t'))
    endif
  finally
    unlet! s:in_flight[l:norm_enc]
  endtry
endfunction

" Opening `foo` directly when only `foo.cott.age` exists on disk.
function! cottage#on_buf_new_file() abort
  if !get(g:, 'cottage_enabled', 1)
    return
  endif

  let l:dec_path = fnamemodify(expand('<afile>'), ':p')
  if empty(l:dec_path) || s:is_encrypted_file(l:dec_path)
    return
  endif

  let l:enc_path = s:get_encrypted_path(l:dec_path)
  if !filereadable(l:enc_path)
    return
  endif

  let l:norm = s:normalize_path(l:dec_path)
  if has_key(s:in_flight, l:norm)
    return
  endif
  let s:in_flight[l:norm] = 1

  try
    if !cottage#ensure_installed()
      return
    endif
    if s:load_decrypted(l:enc_path, l:dec_path) && !get(g:, 'cottage_quiet', 0)
      call cottage#msg("Decrypted " . fnamemodify(l:enc_path, ':t'))
    endif
  finally
    unlet! s:in_flight[l:norm]
  endtry
endfunction

" Encrypt `lines` straight to enc_path via stdin, without any plaintext on disk.
function! s:encrypt_lines(lines, enc_path) abort
  let l:ctg_bin = cottage#find_ctg()
  if empty(l:ctg_bin)
    return {'code': 1, 'output': 'ctg binary not found'}
  endif
  let l:input = join(a:lines, "\n") . "\n"
  let l:cmd = shellescape(l:ctg_bin) . ' tee -- ' . shellescape(a:enc_path)
  let l:prev = getcwd()
  execute 'lcd ' . fnameescape(fnamemodify(a:enc_path, ':h'))
  try
    let l:out = system(l:cmd, l:input)
    return {'code': v:shell_error, 'output': l:out}
  finally
    execute 'lcd ' . fnameescape(l:prev)
  endtry
endfunction

function! cottage#on_buf_write_cmd() abort
  let l:bnr = str2nr(expand('<abuf>'))
  let l:enc_path = getbufvar(l:bnr, 'cottage_encrypted_path', '')
  let l:dec_path = getbufvar(l:bnr, 'cottage_decrypted_path', '')
  if empty(l:enc_path)
    return
  endif

  if s:normalize_path(expand('<afile>')) !=# s:normalize_path(l:dec_path)
    call cottage#error("Refusing to write decrypted content to " . expand('<afile>') . ". Only the secret itself can be saved.")
    return
  endif

  let l:res = s:encrypt_lines(getbufline(l:bnr, 1, '$'), l:enc_path)
  if l:res.code != 0
    call cottage#error("Failed to encrypt " . fnamemodify(l:dec_path, ':t') . ": " . trim(l:res.output))
    return
  endif

  call setbufvar(l:bnr, '&modified', 0)
  if !get(g:, 'cottage_quiet', 0)
    call cottage#msg("Encrypted " . fnamemodify(l:dec_path, ':t'))
  endif
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

  let l:bnr = s:find_buffer_by_path(l:file)
  if l:bnr != -1 && getbufvar(l:bnr, 'cottage_tracked', 0)
    call cottage#warn("Already a cottage secret; just :write it: " . fnamemodify(l:file, ':t'))
    return
  endif

  " Prefer the in-memory buffer (may hold unsaved edits) over the file on disk
  if l:bnr != -1 && bufloaded(l:bnr)
    let l:lines = getbufline(l:bnr, 1, '$')
  elseif filereadable(l:file)
    let l:lines = readfile(l:file)
  else
    call cottage#error("File not found: " . l:file)
    return
  endif

  if !cottage#ensure_installed()
    call cottage#error("ctg binary not found. Install it manually or set g:cottage_auto_install = 1.")
    return
  endif

  let l:root = cottage#get_root(fnamemodify(l:file, ':h'))
  if get(g:, 'cottage_auto_init', 1)
    call cottage#ensure_initialized(l:root)
  endif

  let l:enc_file = s:get_encrypted_path(l:file)
  let l:res = s:encrypt_lines(l:lines, l:enc_file)
  if l:res.code != 0
    call cottage#error("Encryption failed: " . trim(l:res.output))
    return
  endif

  if l:bnr != -1
    execute 'silent! bwipeout! ' . l:bnr
  endif
  execute 'edit ' . fnameescape(l:enc_file)

  call cottage#msg("Encrypted " . fnamemodify(l:file, ':t') . " -> " . fnamemodify(l:enc_file, ':t'))
  if filereadable(l:file)
    call cottage#warn("Plaintext " . fnamemodify(l:file, ':t') . " is still on disk; remove it yourself.")
  endif
endfunction

" ----------------------------------------------------------------------------
" Introspection for Testing
" ----------------------------------------------------------------------------
function! cottage#get_tracked_files() abort
  return deepcopy(s:tracked_files)
endfunction
