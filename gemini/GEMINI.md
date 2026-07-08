# PKM System Instructions (PARA Method)

You are managing my digital garden based on the PARA method.
My digital garden is managed in `/Users/barziv/Documents/digital-garden/Docs` folder
Always adhere to the following rules when researching, writing, or updating information:

## Directory Structure

Assume the following top-level directory structure for the PKM system:

- **Projects**: `/Projects/` - Active efforts with a specific goal and deadline.
- **Areas**: `/Areas/` - Spheres of activity with a standard to be maintained over time (e.g., Health, Finances).
- **Resources**: `/Resources/` - Topics or interests of ongoing usefulness.
- **Archives**: `/Archives/` - Inactive items from the other three categories.

## Workflow Rules

1. **Automatic Resources:** Whenever you synthesize valuable knowledge, architectural insights, or reusable code snippets, automatically write or append this information to the relevant note in the `/Resources/` directory.
2. **Project Updates:** When you complete tasks or make significant progress on larger efforts, automatically update the corresponding notes in the `/Projects/` directory to reflect the current state and next steps.
3. **Consultation for Areas:** If a piece of information or task seems more aligned with long-term responsibilities or ongoing standards (Areas), you MUST ask me for confirmation and specific placement instructions before writing to the `/Areas/` directory.
4. **Formatting:** Ensure all notes use clean Markdown, include relevant tags (e.g., `#resource`, `#project`), and proactively create internal links to related concepts within the digital garden.

_BEFORE YOU WRITE TO THE PKM ASK FOR MY PERMISSION_

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
