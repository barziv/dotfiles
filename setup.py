#!/usr/bin/env python3
"""Symlink dotfiles into their expected locations.

Dry-run by default; pass --apply to make changes. Existing real files/dirs
are renamed to <path>.bak-<timestamp> before being replaced with a symlink.
"""
from __future__ import annotations

import argparse
import difflib
import filecmp
import getpass
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parent
SECRETS_ENV = REPO / ".secrets.env"
ZSH_SECRETS = REPO / "zsh" / "secrets.zsh"
NU_SECRETS  = REPO / "nushell" / "secrets.nu"


@dataclass(frozen=True)
class Secret:
    name: str      # env var name, e.g. "CONTEXT7_API_KEY"
    prompt: str    # human prompt shown when collecting the value


SECRETS: list[Secret] = [
    Secret("CONTEXT7_API_KEY", "Context7 API key (used by Gemini MCP config)"),
    Secret("RENDER_API_KEY",   "Render API key (used by render MCP across claude/opencode/gemini)"),
]

# Repo-relative paths that must be executable. Symlink destinations inherit
# perms from the source, so ensuring +x here covers every consumer.
EXECUTABLES: list[str] = [
    "claude/statusline.sh",
    "tmux/claude_status.sh",
    "tmux/scripts/cal.sh",
]

# Global packages installed via --packages.
NPM_GLOBALS: list[str] = [
    "ccstatusline",
    "@google/gemini-cli",
    "opencode-ai",
    "pnpm",
    "mcp-mongo-server",
]

# Python CLI tools installed via pipx (each in its own venv). Libraries don't
# belong here — they go in PIP_USER. See README for the distinction.
PIPX_TOOLS: list[str] = []

# Python libraries installed via `pip install --user` (importable from any
# Python invocation that sees ~/.local/site-packages).
PIP_USER: list[str] = [
    "requests",
]

# Homebrew formulae installed via --packages. Direct config consumers plus
# tmux-plugin runtime deps (fzf/bat/fd/zoxide).
BREW_PACKAGES: list[str] = [
    "tmux",
    "neovim",
    "nushell",
    "gh",
    "starship",
    "carapace",
    "fzf",
    "bat",
    "fd",
    "zoxide",
    "lazygit",
    "ffmpeg",
    "hugo",
    "awscli",
    "hashicorp/tap/terraform",
    "terminal-notifier",
    "mongosh",
    "agent-browser",
]

# Homebrew casks installed via --packages. GUI apps and terminals.
BREW_CASKS: list[str] = [
    "ghostty",
    "raycast",
    "rectangle",
    "alt-tab",
    "visual-studio-code",
    "slack",
    "bruno",
    "ngrok",
    "burp-suite",
    "TheBoredTeam/boring-notch/boring-notch"
]

# Excluded from directory diff walks.
DIFF_SKIP = {"node_modules", ".git", ".DS_Store", "plugins", "history.txt", "vendor"}

# Max lines of unified diff to print per file before truncating.
MAX_DIFF_LINES = 200


@dataclass(frozen=True)
class Entry:
    src: str           # path within the repo
    dst: str           # destination (may contain ~)
    mode: str          # "folder" or "per-file"


MAPPINGS: list[Entry] = [
    Entry(".agents",  "~/.agents",                                  "folder"),
    Entry("ghostty",  "~/.config/ghostty",                          "folder"),
    Entry("nvim",     "~/.config/nvim",                             "folder"),
    Entry("opencode", "~/.config/opencode",                         "folder"),
    Entry("tmux",     "~/.config/tmux",                             "folder"),
    Entry("nushell",  "~/Library/Application Support/nushell",      "folder"),
    Entry("ccstatusline", "~/.config/ccstatusline",                  "folder"),
    Entry("agent-browser", "~/.agent-browser",                     "per-file"),
    Entry("claude",   "~/.claude",                                  "per-file"),
    Entry("gh",       "~/.config/gh",                               "per-file"),
    Entry("gemini",   "~/.gemini",                                  "per-file"),
    Entry("git",      "~/.config/git",                              "per-file"),
    Entry("starship", "~/.config",                                  "per-file"),
    Entry("zsh",      "~",                                          "per-file"),
]


# --- ANSI color helpers -----------------------------------------------------

USE_COLOR = sys.stdout.isatty()


def c(code: str, s: str) -> str:
    return f"\033[{code}m{s}\033[0m" if USE_COLOR else s


def green(s: str) -> str:  return c("32", s)
def red(s: str) -> str:    return c("31", s)
def yellow(s: str) -> str: return c("33", s)
def cyan(s: str) -> str:   return c("36", s)
def dim(s: str) -> str:    return c("2",  s)


# --- Pair expansion ---------------------------------------------------------

@dataclass(frozen=True)
class Pair:
    entry_name: str   # top-level repo dir, for filtering with --only
    src: Path         # absolute path inside the repo
    dst: Path         # absolute destination path


def expand_pairs(entries: list[Entry]) -> list[Pair]:
    pairs: list[Pair] = []
    for e in entries:
        src_root = REPO / e.src
        dst_root = Path(os.path.expanduser(e.dst))
        if not src_root.exists():
            print(yellow(f"warning: source {src_root} does not exist; skipping"),
                  file=sys.stderr)
            continue
        if e.mode == "folder":
            pairs.append(Pair(e.src, src_root, dst_root))
        elif e.mode == "per-file":
            for child in sorted(src_root.iterdir()):
                pairs.append(Pair(e.src, child, dst_root / child.name))
        else:
            raise ValueError(f"unknown mode {e.mode!r} for {e.src}")
    return pairs


# --- Status -----------------------------------------------------------------

def classify(pair: Pair) -> str:
    dst = pair.dst
    if dst.is_symlink():
        try:
            target = Path(os.readlink(dst))
            if not target.is_absolute():
                target = (dst.parent / target).resolve()
            else:
                target = target.resolve()
            if target == pair.src.resolve():
                return "linked"
        except OSError:
            pass
        return "differs"  # symlink pointing elsewhere
    if not dst.exists():
        return "missing"
    return "same" if contents_equal(pair.src, dst) else "differs"


def contents_equal(a: Path, b: Path) -> bool:
    if a.is_file() and b.is_file():
        return filecmp.cmp(a, b, shallow=False)
    if a.is_dir() and b.is_dir():
        return _dirs_equal(a, b)
    return False


def _dirs_equal(a: Path, b: Path) -> bool:
    a_files = _walk(a)
    b_files = _walk(b)
    if a_files.keys() != b_files.keys():
        return False
    for rel in a_files:
        if not filecmp.cmp(a / rel, b / rel, shallow=False):
            return False
    return True


def _walk(root: Path) -> dict[str, None]:
    out: dict[str, None] = {}
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in DIFF_SKIP]
        for f in files:
            if f in DIFF_SKIP:
                continue
            rel = os.path.relpath(os.path.join(base, f), root)
            out[rel] = None
    return out


# --- Diff rendering ---------------------------------------------------------

def render_diff(pair: Pair) -> None:
    """Print a unified diff between repo source and current destination."""
    src, dst = pair.src, pair.dst
    if dst.is_symlink() or not dst.exists():
        return
    if src.is_file() and dst.is_file():
        _file_diff(src, dst)
    elif src.is_dir() and dst.is_dir():
        _dir_diff(src, dst)
    else:
        print(yellow(f"  cannot diff: type mismatch ({src} vs {dst})"))


def _file_diff(src: Path, dst: Path) -> None:
    try:
        a = dst.read_text().splitlines(keepends=True)
        b = src.read_text().splitlines(keepends=True)
    except UnicodeDecodeError:
        print(dim(f"  <binary file, {dst.stat().st_size} vs {src.stat().st_size} bytes>"))
        return
    diff = list(difflib.unified_diff(a, b, fromfile=str(dst), tofile=str(src)))
    _emit_diff(diff)


def _dir_diff(src: Path, dst: Path) -> None:
    a_files = _walk(dst)
    b_files = _walk(src)
    only_dst = sorted(set(a_files) - set(b_files))
    only_src = sorted(set(b_files) - set(a_files))
    common   = sorted(set(a_files) & set(b_files))
    for rel in only_dst:
        print(red(f"  only in destination: {rel}"))
    for rel in only_src:
        print(green(f"  only in repo:        {rel}"))
    for rel in common:
        a, b = dst / rel, src / rel
        if filecmp.cmp(a, b, shallow=False):
            continue
        print(cyan(f"  --- {rel} ---"))
        try:
            ta = a.read_text().splitlines(keepends=True)
            tb = b.read_text().splitlines(keepends=True)
        except UnicodeDecodeError:
            print(dim(f"  <binary file, {a.stat().st_size} vs {b.stat().st_size} bytes>"))
            continue
        diff = list(difflib.unified_diff(ta, tb, fromfile=str(a), tofile=str(b)))
        _emit_diff(diff, indent="  ")


def _emit_diff(lines: list[str], indent: str = "  ") -> None:
    if not lines:
        return
    shown = lines[:MAX_DIFF_LINES]
    for line in shown:
        line = line.rstrip("\n")
        if line.startswith("+++") or line.startswith("---"):
            out = cyan(line)
        elif line.startswith("+"):
            out = green(line)
        elif line.startswith("-"):
            out = red(line)
        elif line.startswith("@@"):
            out = yellow(line)
        else:
            out = line
        print(f"{indent}{out}")
    if len(lines) > MAX_DIFF_LINES:
        print(dim(f"{indent}... {len(lines) - MAX_DIFF_LINES} more lines"))


# --- Apply ------------------------------------------------------------------

def apply_pair(pair: Pair, status: str) -> None:
    if status == "linked":
        return
    dst = pair.dst
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.is_symlink() or dst.exists():
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = dst.with_name(dst.name + f".bak-{ts}")
        os.rename(dst, backup)
        print(dim(f"  backed up -> {backup}"))
    os.symlink(pair.src.resolve(), dst)
    print(green(f"  linked    {dst} -> {pair.src}"))


# --- Package install --------------------------------------------------------

def _run(cmd: list[str]) -> int:
    print(cyan(f"  $ {' '.join(cmd)}"))
    return subprocess.run(cmd).returncode


def install_npm_globals() -> None:
    if not NPM_GLOBALS:
        return
    if not shutil.which("npm"):
        print(yellow("  npm not found; skipping NPM globals"))
        return
    listed = subprocess.run(
        ["npm", "list", "-g", "--depth=0", "--parseable"],
        capture_output=True, text=True
    ).stdout
    installed = {os.path.basename(line) for line in listed.splitlines() if line}
    for pkg in NPM_GLOBALS:
        # scoped packages: install name `@scope/pkg`, dir name `pkg` under @scope
        name = pkg.split("/")[-1] if pkg.startswith("@") else pkg
        if name in installed:
            print(dim(f"  npm {pkg} already installed"))
            continue
        _run(["npm", "install", "-g", pkg])


def install_pipx_tools() -> None:
    if not PIPX_TOOLS:
        return
    if not shutil.which("pipx"):
        if shutil.which("brew"):
            _run(["brew", "install", "pipx"])
            _run(["pipx", "ensurepath"])
        else:
            print(yellow("  pipx not found and brew unavailable; skipping pipx tools"))
            return
    listed = subprocess.run(
        ["pipx", "list", "--short"], capture_output=True, text=True
    ).stdout
    installed = {line.split()[0] for line in listed.splitlines() if line.strip()}
    for pkg in PIPX_TOOLS:
        if pkg in installed:
            print(dim(f"  pipx {pkg} already installed"))
            continue
        _run(["pipx", "install", pkg])


def install_pip_user() -> None:
    if not PIP_USER:
        return
    pip = shutil.which("pip") or shutil.which("pip3")
    if not pip:
        print(yellow("  pip not found; skipping pip --user packages"))
        return
    listed = subprocess.run(
        [pip, "list", "--user", "--format=freeze"], capture_output=True, text=True
    ).stdout
    installed = {line.split("==")[0].lower() for line in listed.splitlines() if "==" in line}
    for pkg in PIP_USER:
        if pkg.lower() in installed:
            print(dim(f"  pip --user {pkg} already installed"))
            continue
        _run([pip, "install", "--user", pkg])


def _confirm(prompt: str) -> bool:
    try:
        ans = input(f"{prompt} [y/N]: ").strip().lower()
    except EOFError:
        return False
    return ans in ("y", "yes")


def _install_brew(packages: list[str], kind: str, list_flag: str, install_flag: str | None) -> None:
    """Shared formula/cask installer with a single y/N prompt for the missing set."""
    if not packages:
        return
    if not shutil.which("brew"):
        print(yellow(f"  brew not found; skipping Homebrew {kind}s"))
        return
    listed = subprocess.run(
        ["brew", "list", list_flag, "-1"], capture_output=True, text=True
    ).stdout
    installed = {line.strip() for line in listed.splitlines() if line.strip()}
    # tap-qualified names like "hashicorp/tap/terraform" install as "terraform"
    missing = [p for p in packages if p.rsplit("/", 1)[-1] not in installed]
    if not missing:
        print(dim(f"  all Homebrew {kind}s already installed"))
        return
    print(f"  missing ({len(missing)}): {', '.join(missing)}")
    if not _confirm(f"  install {len(missing)} {kind}(s)?"):
        print(dim("  skipped"))
        return
    cmd_prefix = ["brew", "install"] + ([install_flag] if install_flag else [])
    for pkg in missing:
        _run(cmd_prefix + [pkg])


def install_brew_packages() -> None:
    _install_brew(BREW_PACKAGES, kind="formula", list_flag="--formula", install_flag=None)


def install_brew_casks() -> None:
    _install_brew(BREW_CASKS, kind="cask", list_flag="--cask", install_flag="--cask")


def install_agent_browser_chrome() -> None:
    """Download Chrome for Testing for agent-browser. First run only; idempotent."""
    ab = shutil.which("agent-browser")
    if not ab:
        print(yellow("  agent-browser not found; skipping Chrome download"))
        return
    _run([ab, "install"])


def install_tmux_plugins() -> None:
    """Clone tpm and install plugins listed in tmux.conf. Idempotent."""
    tpm = Path(os.path.expanduser("~/.config/tmux/plugins/tpm"))
    if tpm.exists():
        print(dim(f"  tpm already cloned at {tpm}"))
    else:
        tpm.parent.mkdir(parents=True, exist_ok=True)
        _run(["git", "clone", "https://github.com/tmux-plugins/tpm", str(tpm)])
    installer = tpm / "bin" / "install_plugins"
    if installer.exists():
        _run([str(installer)])


def install_packages() -> None:
    print(cyan("Installing Homebrew formulae:"))
    install_brew_packages()
    print(cyan("\nInstalling Homebrew casks:"))
    install_brew_casks()
    print(cyan("\nInstalling NPM globals:"))
    install_npm_globals()
    if PIPX_TOOLS:
        print(cyan("\nInstalling pipx tools:"))
        install_pipx_tools()
    if PIP_USER:
        print(cyan("\nInstalling pip --user packages:"))
        install_pip_user()
    print(cyan("\nDownloading Chrome for agent-browser:"))
    install_agent_browser_chrome()
    print(cyan("\nInstalling tmux plugins:"))
    install_tmux_plugins()


# --- Secrets ----------------------------------------------------------------

def read_secrets_env() -> dict[str, str]:
    """Parse .secrets.env (KEY=VALUE per line). Missing file -> empty dict."""
    if not SECRETS_ENV.exists():
        return {}
    out: dict[str, str] = {}
    for line in SECRETS_ENV.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def write_secrets_env(values: dict[str, str]) -> None:
    lines = ["# Generated by setup.py. Gitignored. Edit values then re-run setup.py --apply.\n"]
    for s in SECRETS:
        if s.name in values:
            lines.append(f'{s.name}="{values[s.name]}"\n')
    SECRETS_ENV.write_text("".join(lines))
    os.chmod(SECRETS_ENV, 0o600)


def prompt_secret(s: Secret) -> str:
    """Prompt until we get a non-empty value. Offer current env var as default."""
    env_default = os.environ.get(s.name, "").strip()
    while True:
        suffix = " [use current env value]" if env_default else ""
        try:
            value = getpass.getpass(f"  {s.prompt}{suffix}: ").strip()
        except EOFError:
            value = ""
        if not value and env_default:
            return env_default
        if value:
            return value
        print(red("    value cannot be empty; try again"))


def collect_secrets() -> dict[str, str]:
    """Load existing values, prompt for any missing ones, write back."""
    values = read_secrets_env()
    needed = [s for s in SECRETS if not values.get(s.name)]
    if needed:
        print(cyan(f"Collecting {len(needed)} secret(s) — input hidden:"))
        for s in needed:
            values[s.name] = prompt_secret(s)
        write_secrets_env(values)
        print(dim(f"  wrote {SECRETS_ENV}\n"))
    return values


def render_zsh_secrets(values: dict[str, str]) -> None:
    lines = ["# Generated by setup.py. Gitignored. Do not edit; edit .secrets.env instead.\n"]
    for s in SECRETS:
        if s.name in values:
            v = values[s.name].replace('"', '\\"')
            lines.append(f'export {s.name}="{v}"\n')
    ZSH_SECRETS.write_text("".join(lines))
    os.chmod(ZSH_SECRETS, 0o600)


def render_nu_secrets(values: dict[str, str]) -> None:
    lines = ["# Generated by setup.py. Gitignored. Do not edit; edit .secrets.env instead.\n"]
    for s in SECRETS:
        if s.name in values:
            v = values[s.name].replace('"', '\\"')
            lines.append(f'$env.{s.name} = "{v}"\n')
    NU_SECRETS.write_text("".join(lines))
    os.chmod(NU_SECRETS, 0o600)


def report_secrets_dry_run() -> None:
    values = read_secrets_env()
    missing = [s.name for s in SECRETS if not values.get(s.name)]
    print(cyan("Secrets:"))
    for s in SECRETS:
        if values.get(s.name):
            print(f"  {green('set    ')} {s.name}")
        else:
            print(f"  {yellow('missing')} {s.name}  {dim('(' + s.prompt + ')')}")
    if missing:
        print(dim(f"  --apply will prompt for {len(missing)} value(s) and render zsh/secrets.zsh + nushell/secrets.nu"))
    else:
        print(dim("  --apply will render zsh/secrets.zsh + nushell/secrets.nu from .secrets.env"))
    print()


# --- Main -------------------------------------------------------------------

STATUS_COLOR = {
    "missing": yellow,
    "linked":  green,
    "differs": red,
    "same":    dim,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true",
                        help="actually install symlinks (default: dry-run)")
    parser.add_argument("--only", nargs="+", metavar="NAME", default=None,
                        help="restrict to specific top-level entries (e.g. zsh nvim)")
    parser.add_argument("--packages", action="store_true",
                        help="install global npm/pipx/pip-user packages and exit")
    args = parser.parse_args()

    if args.packages:
        install_packages()
        return 0

    entries = MAPPINGS
    if args.only:
        wanted = set(args.only)
        entries = [e for e in MAPPINGS if e.src in wanted]
        missing = wanted - {e.src for e in MAPPINGS}
        if missing:
            print(red(f"unknown entries: {', '.join(sorted(missing))}"), file=sys.stderr)
            return 2

    if args.apply:
        for rel in EXECUTABLES:
            p = REPO / rel
            if p.exists() and not (p.stat().st_mode & 0o111):
                p.chmod(p.stat().st_mode | 0o111)
                print(dim(f"  chmod +x {rel}"))
        values = collect_secrets()
        render_zsh_secrets(values)
        render_nu_secrets(values)
        print(dim(f"  rendered {ZSH_SECRETS.relative_to(REPO)} + {NU_SECRETS.relative_to(REPO)}\n"))
    else:
        report_secrets_dry_run()

    pairs = expand_pairs(entries)
    if not pairs:
        print("nothing to do")
        return 0

    mode_label = "APPLY" if args.apply else "DRY-RUN"
    print(cyan(f"[{mode_label}] {len(pairs)} mapping(s)\n"))

    for pair in pairs:
        status = classify(pair)
        color = STATUS_COLOR.get(status, lambda s: s)
        print(f"{color(status.ljust(8))} {pair.dst}  {dim('<- ' + str(pair.src.relative_to(REPO)))}")
        if status == "differs":
            render_diff(pair)
        if args.apply:
            apply_pair(pair, status)
        print()

    if not args.apply:
        print(dim("(dry-run; re-run with --apply to install)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
