# cottage.vim

Transparent age-encrypted secrets management in Vim and Neovim with [Cottage](https://github.com/sayanarijit/cottage).

[![demo](https://asciinema.org/a/1264076.svg)](https://asciinema.org/a/1264076)

`cottage.vim` manages `.cott.age` files transparently:

- **Auto-decrypts** `.cott.age` files into their plaintext form when opened for editing.
- **Auto-detects / downloads** `ctg` using the best available package manager if missing.
- **Syncs on save** (`:w`): re-encrypts the ciphertext sibling while you continue editing.
- **Auto-encrypts and cleans on close**: when closing the buffer (`:bd`, `:bw`, `:q`) or exiting Vim (`:qa`), re-encrypts and deletes the plaintext secret file from disk.
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
   - `cottage.vim` runs `ctg decrypt secret.env.cott.age`.
   - The buffer is loaded as `secret.env` with full syntax highlighting, filetype plugins, and LSP support.

2. **Editing and saving**:
   - Whenever you save with `:w`, `cottage.vim` runs `ctg encrypt secret.env` to keep `secret.env.cott.age` updated.
   - The plaintext file remains available on disk while you are actively working in the buffer.

3. **Closing or exiting**:
   - When you close the buffer (`:bd`, `:bw`, `:q`), or exit the editor (`:qa`), `cottage.vim` runs `ctg encrypt secret.env --clean`.
   - The plaintext file is safely removed from disk, leaving only the encrypted `.cott.age` file.

4. **Auto-downloading `ctg`**:
   - If `ctg` is not found on your system PATH, `cottage.vim` automatically detects the best package manager and installs it.
   - Detection priority: `cargo binstall` → `cargo install` → `uv tool` → `pipx` → `python3 -m pip` → `pnpm` → `yarn` → `npm`.

---

## Commands

| Command                  | Description                                                                                                                                                         |
| :----------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `:CottageEncrypt [file]` | Encrypts the specified file (or current buffer) with `ctg encrypt <file> --clean` and opens the resulting `.cott.age` file. Auto-initializes `.cottage` if missing. |
| `:CottageDecrypt [file]` | Decrypts the specified `.cott.age` file and opens it.                                                                                                               |
| `:CottageInstall`        | Detects the best available package registry and installs `ctg`.                                                                                                     |
| `:CottageInit [dir]`     | Initializes cottage (`ctg init`) in the workspace or specified directory.                                                                                           |
| `:CottageClean`          | Deletes all decrypted secret files in the workspace via `ctg clean -qqq`.                                                                                           |
| `:CottageStatus`         | Displays `ctg status` output in a preview window.                                                                                                                   |
| `:CottageDiff [file]`    | Displays `ctg diff` output in a diff buffer.                                                                                                                        |
| `:CottagePull`           | Pulls upstream cottage secrets.                                                                                                                                     |
| `:CottagePush`           | Pushes cottage secrets upstream.                                                                                                                                    |

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

" Sync encryption on save (default: 1)
let g:cottage_sync_on_save = 1

" Encrypt and delete plaintext on buffer close (default: 1)
let g:cottage_clean_on_close = 1

" Encrypt and delete plaintext when exiting Vim (default: 1)
let g:cottage_clean_on_exit = 1

" Encrypt and delete plaintext on buffer leave / focus switch (default: 1)
let g:cottage_clean_on_leave = 1

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
vim.g.cottage_sync_on_save = 1
vim.g.cottage_clean_on_close = 1
vim.g.cottage_clean_on_exit = 1
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
- **Guaranteed Cleanup**: `VimLeavePre` and `BufUnload` hooks ensure all tracked plaintext secret files are cleanly encrypted and erased from disk.

---

## License

[MIT](LICENSE) © [sayanarijit](https://github.com/sayanarijit)
