# Agent instructions

I use nushell as my standard shell, so any commands you give me to run MUST be nushell-compatible.

## Browser Automation

Use the `agent-browser` CLI for ALL browser tasks. Never use the macOS `open` command. It drives its own isolated Chrome for Testing with compact, token-cheap output.

Always run agent-browser with this agent's own persistent profile flag:

    --profile /Users/barziv/.agent-browser/profiles/opencode

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
