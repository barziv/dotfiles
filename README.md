# dotfiles

My personal configuration files, kept under version control so I can quickly bootstrap a new machine with my preferred setup.

## Contents

| Directory  | Tool                                              |
| ---------- | ------------------------------------------------- |
| `claude/`   | Claude Code CLI configuration                    |
| `gemini/`   | Gemini CLI configuration                         |
| `gh/`       | GitHub CLI configuration                         |
| `ghostty/`  | Ghostty terminal emulator configuration          |
| `git/`      | Git user configuration                           |
| `nushell/`  | Nushell shell configuration                      |
| `nvim/`     | Neovim configuration                             |
| `opencode/` | OpenCode configuration                           |
| `starship/` | Starship prompt configuration                    |
| `tmux/`     | tmux terminal multiplexer configuration          |
| `zsh/`      | Zsh shell configuration                          |

## Setup

On a fresh machine:

```sh
git clone https://github.com/barziv/dotfiles.git ~/Code/dotfiles
cd ~/Code/dotfiles
./setup.py            # dry-run: shows status + diffs
./setup.py --apply    # install symlinks
```

`setup.py` symlinks each config directory into the location its tool expects (e.g. `~/.config/nvim`, `~/.config/ghostty`, `~/.zshrc`). Running without `--apply` prints, for every mapping, whether the destination is missing/linked/same/differs and shows a unified diff against the repo's version. When `--apply` replaces an existing file or directory, it first renames it to `<path>.bak-<timestamp>`.

Restrict to specific entries with `--only`:

```sh
./setup.py --only nvim zsh --apply
```

Install global packages (Homebrew formulae, npm globals, pipx tools, pip --user libraries) and tmux plugins as a separate step:

```sh
./setup.py --packages
```

The package lists live at the top of `setup.py` (`BREW_PACKAGES`, `BREW_CASKS`, `NPM_GLOBALS`, `PIPX_TOOLS`, `PIP_USER`). Idempotent — packages already present are skipped. Homebrew formulae and casks list the missing items and prompt for confirmation before installing. This step also clones [tpm](https://github.com/tmux-plugins/tpm) into `~/.config/tmux/plugins/` and installs every plugin listed in `tmux/tmux.conf`.

## Adding a new tool

1. Create a new top-level directory named after the tool.
2. Copy or move the relevant config files into it.
3. Add an entry to `MAPPINGS` in `setup.py` (use `mode="folder"` to symlink the whole directory, or `mode="per-file"` to symlink each child individually — pick `per-file` when the destination directory holds non-dotfile state like auth tokens).
4. Add a row to the table above.
