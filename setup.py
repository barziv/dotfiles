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
    args = parser.parse_args()

    entries = MAPPINGS
    if args.only:
        wanted = set(args.only)
        entries = [e for e in MAPPINGS if e.src in wanted]
        missing = wanted - {e.src for e in MAPPINGS}
        if missing:
            print(red(f"unknown entries: {', '.join(sorted(missing))}"), file=sys.stderr)
            return 2

    if args.apply:
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
