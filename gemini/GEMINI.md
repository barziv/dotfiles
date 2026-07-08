# PKM System (Diátaxis × Dendron)

You help manage my digital garden at `/Users/barziv/Documents/digital-garden/Docs`.
It uses a Diátaxis × Dendron hybrid — **folder = what the thing is**, **filename = dotted topic hierarchy**. No subfolders; the dots carry the hierarchy and one file holds everything on its topic. See `_framework.md` for the full spec. (This replaces the old PARA layout.)

## Buckets

- `reference/` — facts, configs, notes I look up (information-oriented)
- `how-to/` — steps to accomplish one specific task
- `project/` — active efforts with a goal (work, ideas, things I'm building/buying)
- `moments/` — trips, experiences, events (dated things that happened)
- `personal-growth/` — learning, self-development, running personal lists

Add a new bucket only when content genuinely fits none of these.

## Public vs Private

- Everything lives in `Private/` by default.
- Nothing is published automatically. To publish, **manually copy** a note into `Public/` (same bucket folders) — and only when I ask.

## Naming rules

- Don't repeat the folder name in the filename (the folder already says the kind).
- Hierarchy goes in the filename, segments separated by `.`: `reference/tech.docker.awesome-compose.md`
- Multi-word segment uses `-`: `...awesome-compose...`
- Hebrew is allowed in filenames; keep an English topic prefix for grouping: `project/נדלן-דניאל-טל-revo.md`
- Internal links are Obsidian wikilinks against the full filename: `[[reference/tech.git.worktrees]]`

## Workflow

- When you synthesize reusable knowledge (configs, snippets, insights), append it to the right `reference/` note; progress on an effort updates the matching `project/` note.
- Use clean Markdown and create wikilinks to related notes.

_BEFORE YOU WRITE TO THE PKM, ASK FOR MY PERMISSION._

About my mac, I use nushell as my standard shell so when you give me commands to run they MUST be compatible with nushell

## Browser Automation

Use the `agent-browser` CLI for ALL browser tasks (prefer it over the Playwright MCP and any `open` command). It drives its own isolated Chrome for Testing with compact, token-cheap output.

Always run agent-browser with this agent's own persistent profile flag:

    --profile /Users/barziv/.agent-browser/profiles/gemini

It keeps the browser isolated with its own logins (its own Google/X/etc. accounts, separate from my personal Chrome). Log in once in the window and it persists. The commands below omit the flag for brevity — include it on every call.

Core loop:

    agent-browser open <url>        # navigate
    agent-browser snapshot          # accessibility tree with @refs — prefer over screenshots (cheap)
    agent-browser click @e3         # act on a ref from the snapshot
    agent-browser read              # rendered markdown/DOM of the current tab
    agent-browser screenshot out.png
    agent-browser close             # end the session

Run `agent-browser skills` (and `agent-browser skills get <name>`) for the full, version-matched command reference. First run only: `agent-browser install` downloads Chrome.

Security: an agent with its own logged-in accounts running autonomously is a prompt-injection surface. Only point it at sites/environments I'm comfortable with it acting in.
