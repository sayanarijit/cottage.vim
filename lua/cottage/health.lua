local M = {}

local health = vim.health or require("health")

M.check = function()
  health.start("cottage.vim")

  -- Check ctg binary
  local ctg_bin = vim.fn["cottage#find_ctg"]()
  if ctg_bin ~= "" then
    local version = vim.fn.system(ctg_bin .. " --version")
    health.ok(string.format("Found 'ctg' binary at %s (%s)", ctg_bin, vim.trim(version)))
  else
    health.error("Could not find 'ctg' binary on PATH or standard directories.", {
      "Run :CottageInstall to automatically install cottage",
      "Or install manually: cargo install cottage / uv tool install cottage / npm i -g @sayanarijit/cottage",
    })
  end

  -- Check package managers
  local installer = vim.fn["cottage#detect_best_installer"]()
  if installer and installer.label then
    health.ok(string.format("Best available installer: %s", installer.label))
  else
    health.warn("No supported installer detected (cargo, uv, pipx, python3, pnpm, yarn, npm)")
  end

  -- Check workspace
  local root = vim.fn["cottage#get_root"](vim.fn.getcwd())
  if vim.fn.isdirectory(root .. "/.cottage") == 1 then
    health.ok(string.format("Cottage workspace initialized at: %s", root))
  else
    health.info(string.format("No .cottage directory in %s. Run :CottageInit to initialize.", root))
  end

  -- Check settings
  local get_setting = function(var, default)
    local val = vim.g[var]
    if val ~= nil then
      return val ~= 0
    end
    return default
  end

  local enabled = get_setting("cottage_enabled", true)
  local auto_install = get_setting("cottage_auto_install", true)
  local sync_save = get_setting("cottage_sync_on_save", true)
  local clean_close = get_setting("cottage_clean_on_close", true)
  local clean_exit = get_setting("cottage_clean_on_exit", true)
  local clean_leave = get_setting("cottage_clean_on_leave", true)
  local disable_swapfile = get_setting("cottage_disable_swapfile", true)
  local disable_backup = get_setting("cottage_disable_backup", true)
  local disable_undofile = get_setting("cottage_disable_undofile", true)

  health.ok(string.format(
    "Configuration: enabled=%s, auto_install=%s, sync_on_save=%s, clean_on_close=%s, clean_on_exit=%s, clean_on_leave=%s, disable_swapfile=%s, disable_backup=%s, disable_undofile=%s",
    tostring(enabled), tostring(auto_install), tostring(sync_save), tostring(clean_close),
    tostring(clean_exit), tostring(clean_leave), tostring(disable_swapfile), tostring(disable_backup),
    tostring(disable_undofile)
  ))
end

return M
