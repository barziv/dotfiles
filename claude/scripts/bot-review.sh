#!/usr/bin/env bash
# bot-review.sh — runs the GitHub `Claude Code Review` bot's own review locally, before the push.
#
# The prompt, model, effort and tools come from .github/workflows/claude-code-review.yml, so
# this stays in step with the bot, and it runs in a fresh `claude -p` session, as the bot does,
# not anchored on the session that wrote the code. Two differences: it reviews the local
# branch, not the PR (the commits are not pushed yet), and it prints the high findings as a
# JSON array instead of posting them.
#
# Usage: bot-review.sh [out-file]     run from the repo; prints the JSON, and saves it to out-file
#        bot-review.sh --dry          print the prompt and the claude command, run nothing

set -euo pipefail

SCRIPTS=$(dirname "$0") exec python3 - "$@" <<'PY'
import os, re, shlex, subprocess, sys

def git(*args):
    return subprocess.run(['git', *args], check=True, capture_output=True, text=True).stdout.strip()

root = git('rev-parse', '--show-toplevel')
branch = git('branch', '--show-current')
url = git('remote', 'get-url', 'origin')
repo = re.sub(r'\.git$', '', re.split(r'github\.com[:/]', url)[-1])
workflow = os.path.join(root, '.github/workflows/claude-code-review.yml')

def block(key):
    """The YAML block scalar `key: |` in the workflow, with its indent removed."""
    lines = open(workflow).read().split('\n')
    for i, line in enumerate(lines):
        if line.strip() == f'{key}: |':
            indent = len(line) - len(line.lstrip()) + 1
            body = []
            for next_line in lines[i + 1:]:
                if next_line.strip() and len(next_line) - len(next_line.lstrip()) < indent:
                    break
                body.append(next_line)
            depth = min(len(l) - len(l.lstrip()) for l in body if l.strip())
            return '\n'.join(l[depth:] for l in body).strip()
    sys.exit(f'bot-review: no `{key}: |` in {workflow}')

prompt = (block('prompt')
    .replace('pull request #${{ github.event.pull_request.number }}', f'branch `{branch}`')
    .replace('${{ github.event.pull_request.number }}', branch)
    .replace('${{ github.repository }}', repo))
prompt += f'''

This is a local run before the push, not on GitHub. The commits are not pushed yet, so the
target is the local branch `{branch}`, and there is no inline-comment tool. Do steps 1 and 2 as
written. Instead of steps 3 and 4, print only a JSON array of the high findings, each
{{"file", "line", "summary", "failure_scenario"}}, with what the comment would have said, or
`[]` when no finding is high. Print nothing else.'''

base = subprocess.run([os.path.join(os.environ['SCRIPTS'], 'push-review.sh'), 'base'],
                      capture_output=True, text=True).stdout.strip()
if base and not base.startswith('origin/'):
    # On GitHub the PR's base is the parent branch, so the bot sees only this layer's diff.
    prompt += f'''

The branch is stacked on `{base}`, and its PR targets `{base}`. Review only `git diff {base}...HEAD`:
the commits from `{base}` are reviewed in their own PR.'''

args = shlex.split(block('claude_args'))
flags = dict(zip(args[::2], args[1::2]))
# The skill reads a local branch with git, not `gh pr diff`; there is nothing to post.
tools = [t for t in flags['--allowedTools'].split(',') if not t.startswith('mcp__github_inline_comment')]
tools += [f'Bash(git {c}:*)' for c in ('diff', 'log', 'show', 'merge-base', 'rev-parse', 'branch', 'status')]

command = ['claude', '-p', prompt, '--output-format', 'text',
           '--model', flags['--model'], '--effort', flags['--effort'],
           '--allowedTools', ','.join(tools)]
if '--disallowedTools' in flags:
    command += ['--disallowedTools', flags['--disallowedTools']]

if sys.argv[1:] == ['--dry']:
    print(prompt, '\n---\n', shlex.join(command[:2] + ['<prompt>'] + command[3:]))
    sys.exit(0)

env = {k: v for k, v in os.environ.items() if k != 'CLAUDECODE'}
print(f'bot-review: {branch} with {flags["--model"]}, effort {flags["--effort"]}', file=sys.stderr)
result = subprocess.run(command, cwd=root, env=env, stdin=subprocess.DEVNULL,
                        capture_output=True, text=True, timeout=1800)
if result.returncode != 0:
    sys.exit(f'bot-review: claude failed ({result.returncode}): {result.stderr.strip()}')

out = result.stdout.strip()
if len(sys.argv) > 1:
    open(sys.argv[1], 'w').write(out + '\n')
print(out)
PY
