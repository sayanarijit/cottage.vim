" ============================================================================
" Tests for cottage.vim
" ============================================================================

set nomore
set shortmess+=a
set noswapfile

let s:test_failures = 0
let s:test_count = 0

function! Assert(condition, msg) abort
  let s:test_count += 1
  if !a:condition
    let s:test_failures += 1
    echohl ErrorMsg
    echomsg 'FAIL: ' . a:msg
    echohl None
  else
    echohl MoreMsg
    echomsg 'PASS: ' . a:msg
    echohl None
  endif
endfunction

function! AssertEqual(actual, expected, msg) abort
  let s:test_count += 1
  if a:actual !=# a:expected
    let s:test_failures += 1
    echohl ErrorMsg
    echomsg 'FAIL: ' . a:msg . ' (expected: ' . string(a:expected) . ', got: ' . string(a:actual) . ')'
    echohl None
  else
    echohl MoreMsg
    echomsg 'PASS: ' . a:msg
    echohl None
  endif
endfunction

function! RunAllTests() abort
  let l:test_dir = tempname() . '_cottage_test'
  call mkdir(l:test_dir, 'p')
  let l:orig_cwd = getcwd()
  execute 'cd ' . fnameescape(l:test_dir)

  try
    " Test 1: Find ctg
    echomsg '--- Test 1: Binary detection ---'
    let l:ctg = cottage#find_ctg()
    call Assert(!empty(l:ctg), 'cottage#find_ctg() returns binary')

    " Test 2: Best installer detection
    echomsg '--- Test 2: Installer detection ---'
    let l:inst = cottage#detect_best_installer()
    call Assert(!empty(l:inst), 'cottage#detect_best_installer() detects installer')
    echomsg 'Detected installer: ' . get(l:inst, 'label', 'none')

    " Test 3: Workspace init & root
    echomsg '--- Test 3: Workspace init & root ---'
    call system('git init -q')
    let l:root = cottage#get_root(l:test_dir)
    call AssertEqual(fnamemodify(l:root, ':p'), fnamemodify(l:test_dir, ':p'), 'cottage#get_root finds repo root')
    call cottage#ensure_initialized(l:root)
    call Assert(isdirectory(l:test_dir . '/.cottage'), '.cottage directory created by ensure_initialized')

    " Test 4: Open & decrypt in memory
    echomsg '--- Test 4: Open & Decrypt *.cott.age ---'
    call system('ctg tee app.env.cott.age', "MY_SECRET=supersecret123\n")
    call Assert(filereadable(l:test_dir . '/app.env.cott.age'), 'app.env.cott.age created via stdin')
    call Assert(!filereadable(l:test_dir . '/app.env'), 'no plaintext app.env on disk')

    edit app.env.cott.age
    call AssertEqual(expand('%:t'), 'app.env', 'Active buffer changed to app.env')
    call AssertEqual(getline(1), 'MY_SECRET=supersecret123', 'Decrypted content matches original secret')
    call Assert(get(b:, 'cottage_tracked', 0) == 1, 'Buffer is marked as cottage_tracked')
    call AssertEqual(&l:buftype, 'acwrite', 'buffer is acwrite')
    call Assert(!&l:swapfile, 'swapfile is disabled on decrypted buffer')
    call Assert(!&l:backup, 'backup is disabled on decrypted buffer')
    call Assert(!&l:writebackup, 'writebackup is disabled on decrypted buffer')
    call Assert(!&l:undofile, 'undofile is disabled by default on decrypted buffer')
    call Assert(!filereadable(l:test_dir . '/app.env'), 'Plaintext app.env NOT on disk while open')

    " Test 5: Edit and save
    echomsg '--- Test 5: Edit & Save ---'
    call setline(1, 'MY_SECRET=modified_secret_456')
    write
    call Assert(!&modified, 'buffer unmodified after save')
    call Assert(!filereadable(l:test_dir . '/app.env'), 'Plaintext app.env NOT on disk after save')

    " Test 6: Close and re-open
    echomsg '--- Test 6: Close and re-open ---'
    bwipeout
    call Assert(filereadable(l:test_dir . '/app.env.cott.age'), 'app.env.cott.age remains on disk')
    edit app.env.cott.age
    call AssertEqual(getline(1), 'MY_SECRET=modified_secret_456', 'Re-decrypted content matches updated value')
    " Writing elsewhere is refused
    silent! write other_plain.txt
    call Assert(!filereadable(l:test_dir . '/other_plain.txt'), 'writing decrypted buffer to another path is refused')
    bwipeout

    " Test 7: :CottageEncrypt on a file argument
    echomsg '--- Test 7: :CottageEncrypt command ---'
    call writefile(['DATABASE_URL=postgres://localhost/db'], l:test_dir . '/db.env')
    CottageEncrypt db.env
    call Assert(filereadable(l:test_dir . '/db.env.cott.age'), 'db.env.cott.age created after CottageEncrypt')
    call AssertEqual(expand('%:t'), 'db.env', 'Active buffer is db.env after CottageEncrypt')
    call Assert(get(b:, 'cottage_tracked', 0) == 1, 'Buffer is cottage_tracked after CottageEncrypt')
    call AssertEqual(getline(1), 'DATABASE_URL=postgres://localhost/db', 'Decrypted content loaded after CottageEncrypt')
    bwipeout

    " Test 8: :CottageEncrypt on current buffer (unsaved edits are encrypted)
    echomsg '--- Test 8: :CottageEncrypt on current buffer ---'
    call writefile(['API_KEY=old'], l:test_dir . '/api.env')
    edit api.env
    call setline(1, 'API_KEY=secret_key_789')
    CottageEncrypt
    call Assert(filereadable(l:test_dir . '/api.env.cott.age'), 'api.env.cott.age created')
    call AssertEqual(expand('%:t'), 'api.env', 'Active buffer is api.env')
    call Assert(get(b:, 'cottage_tracked', 0) == 1, 'Buffer is cottage_tracked')
    call AssertEqual(getline(1), 'API_KEY=secret_key_789', 'Unsaved buffer content was encrypted')
    bwipeout

    " Test 10: Hidden buffers and splits keep content, nothing hits disk
    echomsg '--- Test 10: Buffer switching ---'
    set hidden
    call writefile(['OTHER_CONTENT'], l:test_dir . '/other.txt')
    edit app.env.cott.age
    edit other.txt
    b app.env
    call AssertEqual(getline(1), 'MY_SECRET=modified_secret_456', 'content preserved after switching')
    call setline(1, 'MY_SECRET=final_secret_999')
    write
    b other.txt
    call Assert(!filereadable(l:test_dir . '/app.env'), 'no plaintext on disk after switching')
    bwipeout! app.env
    bwipeout! other.txt
    edit app.env.cott.age
    call AssertEqual(getline(1), 'MY_SECRET=final_secret_999', 'saved content persisted')
    vsplit other.txt
    close!
    call Assert(!filereadable(l:test_dir . '/app.env'), 'no plaintext on disk after split closed')
    bwipeout! app.env

    " Test 11: Open decrypted path directly
    echomsg '--- Test 11: Open decrypted path directly ---'
    edit app.env
    call AssertEqual(getline(1), 'MY_SECRET=final_secret_999', 'Opening decrypted path directly decrypts content')
    call Assert(get(b:, 'cottage_tracked', 0) == 1, 'Buffer is cottage_tracked when opened directly')
    call Assert(!filereadable(l:test_dir . '/app.env'), 'no plaintext on disk')
    call setline(1, 'MY_SECRET=via_direct')
    write
    bwipeout!
    edit app.env.cott.age
    call AssertEqual(getline(1), 'MY_SECRET=via_direct', 'write from directly opened buffer persisted')
    bwipeout!

    " Test 12: Untracked buffers untouched
    echomsg '--- Test 12: Untracked buffers ---'
    edit other.txt
    write
    call Assert(!filereadable(l:test_dir . '/other.txt.cott.age'), 'other.txt was NOT encrypted')
    bwipeout!

    execute 'cd ' . fnameescape(l:orig_cwd)
    call delete(l:test_dir, 'rf')
  endtry

  echomsg '========================================'
  echomsg 'Results: ' . s:test_count . ' tests, ' . s:test_failures . ' failures.'
  echomsg '========================================'

  if s:test_failures > 0
    cquit!
  endif
endfunction
