# cottage.vim

Transparent age-encrypted secrets management in Vim and Neovim with [Cottage](https://github.com/sayanarijit/cottage).

`cottage.vim` manages `.cott.age` files transparently:

- **Auto-decrypts** `.cott.age` files into their plaintext form when opened for editing.
- **Auto-detects / downloads** `ctg` using the best available package manager if missing.
- **Encrypts on save** (`:w`): pipes the buffer straight into `ctg` and updates the ciphertext.
- **Memory only**: plaintext is never written to disk; secrets live only in the editor buffer.
- **Safe by default**: automatically disables swapfiles, backup files, and persistent undofiles on decrypted buffers to prevent secrets from leaking into disk caches.

---

## Installation

### vim pack (nvim native)

```lua
vim.pack.add({
  'https://github.com/sayanarijit/cottage.vim',
})
```

### [lazy.nvim](https://github.com/folke/lazy.nvim) (Neovim)

```lua
{
  "sayanarijit/cottage.vim",
  event = "VeryLazy",
}
```

### [vim-plug](https://github.com/junegunn/vim-plug) (Vim / Neovim)

```vim
Plug 'sayanarijit/cottage.vim'
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim) (Neovim)

```lua
use 'sayanarijit/cottage.vim'
```

### Native Package (Vim 8+ / Neovim)

```bash
git clone https://github.com/sayanarijit/cottage.vim ~/.vim/pack/plugins/start/cottage.vim
```

---

## How It Works

1. **Opening a `.cott.age` file**:
   When you run `vim secret.env.cott.age` or `:edit secret.env.cott.age`:
   - `cottage.vim` runs `ctg cat -- secret.env.cott.age` and loads the output into an in-memory buffer.
   - The buffer is named `secret.env` with full syntax highlighting, filetype plugins, and LSP support.

2. **Editing and saving**:
   - Whenever you save with `:w`, `cottage.vim` passes the buffer content to the stdin of `ctg tee secret.env.cott.age`, which re-encrypts it.
   - No plaintext file is ever created on disk.

3. **Closing or exiting**:
   - Nothing to clean up: closing the buffer simply discards the in-memory plaintext.

4. **Auto-downloading `ctg`**:
   - If `ctg` is not found on your system PATH, `cottage.vim` automatically detects the best package manager and installs it.
   - Detection priority: `cargo binstall` → `cargo install` → `uv tool` → `pipx` → `python3 -m pip` → `pnpm` → `yarn` → `npm`.

---

## Commands

| Command                  | Description                                                                                                                                                                                                        |
| :----------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `:CottageEncrypt [file]` | Encrypts the specified file (or current buffer) from memory via `ctg tee` and opens the resulting `.cott.age` file. Auto-initializes `.cottage` if missing. The original plaintext file is left for you to remove. |

---

## Configuration

You can customize the behavior in your `~/.vimrc` or `init.lua`:

### Vimscript (`~/.vimrc`)

```vim
" Enable / disable the plugin (default: 1)
let g:cottage_enabled = 1

" Auto-install ctg if missing when opening a .cott.age file (default: 1)
let g:cottage_auto_install = 1

" Custom path to ctg binary (default: auto-detected)
let g:cottage_bin = ''

" Auto-run ctg init if needed during :CottageEncrypt (default: 1)
let g:cottage_auto_init = 1

" Disable swapfiles on decrypted buffers (default: 1)
let g:cottage_disable_swapfile = 1

" Disable backup files on decrypted buffers (default: 1)
let g:cottage_disable_backup = 1

" Disable persistent undofile on decrypted buffers (default: 1)
let g:cottage_disable_undofile = 1

" Suppress informational echo messages (default: 0)
let g:cottage_quiet = 0
```

### Lua (`init.lua`)

```lua
vim.g.cottage_enabled = 1
vim.g.cottage_auto_install = 1
vim.g.cottage_disable_swapfile = 1
vim.g.cottage_disable_backup = 1
vim.g.cottage_disable_undofile = 1
```

---

## Health Check (Neovim)

Run `:checkhealth cottage` in Neovim to verify your environment:

- Verifies `ctg` binary detection and version.
- Lists detected package managers.
- Checks workspace cottage initialization status.
- Displays current plugin configuration.

---

## Safety Model

`cottage.vim` enforces secret safety in your editor:

- **No Swapfile Leaks**: `noswapfile` prevents secret plaintext from being written into `.swp` swap files.
- **No Backup Leaks**: `nobackup` and `nowritebackup` prevent secret plaintext backups on disk.
- **No Undofile Leaks**: `noundofile` prevents persistent undo history containing plaintext secrets from being written to disk.
- **No Plaintext on Disk**: secrets are decrypted with `ctg cat` and re-encrypted via `ctg tee` stdin, so no decrypted file is ever created. `:w` to any other path is refused.

---

## License

[MIT](LICENSE) © [sayanarijit](https://github.com/sayanarijit)
