function! health#cottage#check() abort
  if exists('*health#report_start')
    call health#report_start('cottage.vim')
  endif

  let l:ctg_bin = cottage#find_ctg()
  if !empty(l:ctg_bin)
    let l:ver = trim(system(shellescape(l:ctg_bin) . ' --version'))
    if exists('*health#report_ok')
      call health#report_ok(printf("Found 'ctg' binary at %s (%s)", l:ctg_bin, l:ver))
    endif
  else
    if exists('*health#report_error')
      call health#report_error("Could not find 'ctg' binary on PATH.", [
            \ "Run :CottageInstall to automatically install cottage",
            \ "Or install manually via cargo/uv/npm"
            \ ])
    endif
  endif

  let l:installer = cottage#detect_best_installer()
  if !empty(l:installer)
    if exists('*health#report_ok')
      call health#report_ok("Best available installer: " . l:installer.label)
    endif
  else
    if exists('*health#report_warn')
      call health#report_warn("No supported installer detected (cargo, uv, pipx, python3, pnpm, yarn, npm)")
    endif
  endif

  let l:root = cottage#get_root(getcwd())
  if isdirectory(l:root . '/.cottage')
    if exists('*health#report_ok')
      call health#report_ok("Cottage workspace initialized at: " . l:root)
    endif
  else
    if exists('*health#report_info')
      call health#report_info("No .cottage directory in " . l:root . ". Run :CottageInit to initialize.")
    endif
  endif
endfunction
