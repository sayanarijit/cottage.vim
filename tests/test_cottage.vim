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

    " Test 4: Create plaintext and encrypt via ctg
    echomsg '--- Test 4: Open & Decrypt *.cott.age ---'
    call writefile(['MY_SECRET=supersecret123'], l:test_dir . '/app.env')
    call system('ctg encrypt app.env --clean')
    call Assert(!filereadable(l:test_dir . '/app.env'), 'app.env cleaned by ctg encrypt --clean')
    call Assert(filereadable(l:test_dir . '/app.env.cott.age'), 'app.env.cott.age exists')

    " Open the .cott.age file
    edit app.env.cott.age
    call AssertEqual(expand('%:t'), 'app.env', 'Active buffer changed to app.env')
    call AssertEqual(getline(1), 'MY_SECRET=supersecret123', 'Decrypted content matches original secret')
    call Assert(get(b:, 'cottage_tracked', 0) == 1, 'Buffer is marked as cottage_tracked')
    call Assert(filereadable(l:test_dir . '/app.env'), 'Plaintext app.env exists on disk while open')

    " Test 5: Edit and save (sync on save)
    echomsg '--- Test 5: Edit & Save (Sync) ---'
    call setline(1, 'MY_SECRET=modified_secret_456')
    write
    call Assert(filereadable(l:test_dir . '/app.env'), 'Plaintext app.env still exists after save')
    call Assert(filereadable(l:test_dir . '/app.env.cott.age'), 'app.env.cott.age exists after save')

    " Test 6: Close buffer (auto clean on close)
    echomsg '--- Test 6: Close buffer (Auto-clean) ---'
    bwipeout
    call Assert(!filereadable(l:test_dir . '/app.env'), 'Plaintext app.env removed from disk after buffer close')
    call Assert(filereadable(l:test_dir . '/app.env.cott.age'), 'app.env.cott.age remains on disk')

    " Test 7: Re-open and verify modified content
    echomsg '--- Test 7: Re-open to verify saved ciphertext ---'
    edit app.env.cott.age
    call AssertEqual(getline(1), 'MY_SECRET=modified_secret_456', 'Re-decrypted content matches updated value')
    bwipeout

    " Test 8: :CottageEncrypt command on a file argument
    echomsg '--- Test 8: :CottageEncrypt command ---'
    call writefile(['DATABASE_URL=postgres://localhost/db'], l:test_dir . '/db.env')
    call Assert(filereadable(l:test_dir . '/db.env'), 'db.env created')
    CottageEncrypt db.env
    call Assert(filereadable(l:test_dir . '/db.env.cott.age'), 'db.env.cott.age created after CottageEncrypt')
    call AssertEqual(expand('%:t'), 'db.env', 'Active buffer is db.env after CottageEncrypt')
    call Assert(get(b:, 'cottage_tracked', 0) == 1, 'Buffer is cottage_tracked after CottageEncrypt')
    call AssertEqual(getline(1), 'DATABASE_URL=postgres://localhost/db', 'Decrypted content loaded after CottageEncrypt')
    bwipeout
    call Assert(!filereadable(l:test_dir . '/db.env'), 'db.env cleaned after bwipeout')

    " Test 9: :CottageEncrypt on current buffer without args
    echomsg '--- Test 9: :CottageEncrypt on current buffer ---'
    call writefile(['API_KEY=secret_key_789'], l:test_dir . '/api.env')
    edit api.env
    call AssertEqual(expand('%:t'), 'api.env', 'api.env opened in buffer')
    CottageEncrypt
    call Assert(filereadable(l:test_dir . '/api.env.cott.age'), 'api.env.cott.age created after CottageEncrypt current buffer')
    call AssertEqual(expand('%:t'), 'api.env', 'Active buffer is api.env after CottageEncrypt current buffer')
    call Assert(get(b:, 'cottage_tracked', 0) == 1, 'Buffer is cottage_tracked after CottageEncrypt current buffer')
    call AssertEqual(getline(1), 'API_KEY=secret_key_789', 'Buffer content matches after CottageEncrypt current buffer')
    bwipeout
    call Assert(!filereadable(l:test_dir . '/api.env'), 'api.env cleaned after bwipeout')

    " Test 10: :CottageDecrypt command
    echomsg '--- Test 10: :CottageDecrypt command ---'
    CottageDecrypt db.env.cott.age
    call AssertEqual(expand('%:t'), 'db.env', 'Buffer is db.env after CottageDecrypt')
    call AssertEqual(getline(1), 'DATABASE_URL=postgres://localhost/db', 'Decrypted content matches via command')
    bwipeout

    " Test 11: Clean on exit
    echomsg '--- Test 11: Clean on VimLeavePre ---'
    edit app.env.cott.age
    call Assert(filereadable(l:test_dir . '/app.env'), 'app.env decrypted on open')
    call cottage#on_vim_leave()
    call Assert(!filereadable(l:test_dir . '/app.env'), 'app.env cleaned on vim leave')
    bwipeout!

    " Test 12: Buffer switching with hidden enabled (clean on hide, restore on enter)
    echomsg '--- Test 12: Buffer switching (BufHidden / BufEnter) ---'
    set hidden
    call writefile(['OTHER_CONTENT'], l:test_dir . '/other.txt')
    edit app.env.cott.age
    call Assert(filereadable(l:test_dir . '/app.env'), 'app.env decrypted on open')
    call AssertEqual(getline(1), 'MY_SECRET=modified_secret_456', 'app.env has expected secret')

    " Switch away to other.txt
    edit other.txt
    call AssertEqual(expand('%:t'), 'other.txt', 'Active buffer changed to other.txt')
    call Assert(!filereadable(l:test_dir . '/app.env'), 'app.env cleaned from disk when hidden')

    " Switch back to app.env
    b app.env
    call AssertEqual(expand('%:t'), 'app.env', 'Active buffer changed back to app.env')
    call Assert(filereadable(l:test_dir . '/app.env'), 'app.env restored on disk upon buffer re-entry')
    call AssertEqual(getline(1), 'MY_SECRET=modified_secret_456', 'app.env content preserved')

    " Edit, save, and switch away again
    call setline(1, 'MY_SECRET=final_secret_999')
    write
    b other.txt
    call Assert(!filereadable(l:test_dir . '/app.env'), 'app.env cleaned after modified buffer hidden')

    " Clean up hidden buffer
    bwipeout! app.env
    bwipeout! other.txt

    " Test 13: Split windows (do not clean while buffer is visible in another window)
    echomsg '--- Test 13: Split windows ---'
    edit app.env.cott.age
    call Assert(filereadable(l:test_dir . '/app.env'), 'app.env decrypted on open')
    vsplit other.txt
    call AssertEqual(expand('%:t'), 'other.txt', 'New split window is other.txt')
    call Assert(filereadable(l:test_dir . '/app.env'), 'app.env remains on disk while still visible in window 1')
    wincmd p
    call AssertEqual(expand('%:t'), 'app.env', 'Focused window 1 (app.env)')
    call Assert(filereadable(l:test_dir . '/app.env'), 'app.env still on disk')
    close!
    call Assert(!filereadable(l:test_dir . '/app.env'), 'app.env cleaned when hidden after window closed')
    " Test 14: Multiple files open on exit (do not encrypt untracked files)
    echomsg '--- Test 14: Multiple files open on exit ---'
    call writefile(['UNTOUCHED_NORMAL_CONTENT'], l:test_dir . '/plain.txt')
    edit plain.txt
    vsplit app.env.cott.age
    call Assert(filereadable(l:test_dir . '/app.env'), 'app.env decrypted on open')
    call Assert(filereadable(l:test_dir . '/plain.txt'), 'plain.txt exists on disk')
    call cottage#on_vim_leave()
    call Assert(!filereadable(l:test_dir . '/app.env'), 'app.env cleaned on exit')
    call Assert(filereadable(l:test_dir . '/plain.txt'), 'plain.txt still exists on disk')
    call Assert(!filereadable(l:test_dir . '/plain.txt.cott.age'), 'plain.txt was NOT encrypted')
    bwipeout! app.env
    bwipeout! plain.txt

    " Test 15: BufUnload sequence during exit does not leak tracking to untracked buffers
    echomsg '--- Test 15: BufUnload sequence with untracked buffers ---'
    call writefile(['OTHER_NORMAL_CONTENT'], l:test_dir . '/other2.txt')
    edit other2.txt
    edit app.env.cott.age
    " While app.env is the active buffer, trigger unload on other2.txt
    let l:other_bnr = bufnr(l:test_dir . '/other2.txt')
    if l:other_bnr > 0
      execute 'bwipeout ' . l:other_bnr
    endif
    call Assert(filereadable(l:test_dir . '/other2.txt'), 'other2.txt exists after wipeout')
    call Assert(!filereadable(l:test_dir . '/other2.txt.cott.age'), 'other2.txt was NOT encrypted upon unload')
    bwipeout! app.env
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
