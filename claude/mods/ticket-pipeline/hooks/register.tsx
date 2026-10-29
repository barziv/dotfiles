import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Check, Pipeline, Pr } from '../types'

// The band above the prompt, two rows:
// - the ticket pipeline, from the state ~/.claude/scripts/pipeline.sh keeps in
//   <git-dir>/claude-pipeline/state.json (the user's reviews happen in Plannotator);
// - the current branch's PR and its CI checks, from `gh pr view`.

const STAGES: [key: string, label: string][] = [
  ['plan', 'plan'],
  ['plan-review', 'review'],
  ['plan-you', 'you'],
  ['code', 'code'],
  ['test', 'test'],
  ['cr', 'CR'],
  ['you', 'you'],
]

// Seconds between PR polls: fast while checks run, slow otherwise.
const PR_FAST = 15
const PR_SLOW = 60
const PASSING = ['SUCCESS', 'NEUTRAL', 'SKIPPED']

const pipeline = atom({ plugin: 'ticket-pipeline', key: 'pipeline' } as const, null)
const pr = atom({ plugin: 'ticket-pipeline', key: 'pr' } as const, null)

type RollupItem = {
  __typename?: string
  name?: string
  context?: string
  status?: string
  conclusion?: string
  state?: string
  detailsUrl?: string
  targetUrl?: string
}

// Collapses gh's statusCheckRollup (check runs and commit statuses) into counts.
const summarize = (items: RollupItem[]) => {
  let passed = 0
  let pending = 0
  const failed: Check[] = []
  for (const c of items) {
    const name = c.name ?? c.context ?? '?'
    const url = c.detailsUrl ?? c.targetUrl ?? ''
    if (c.__typename === 'StatusContext') {
      if (c.state === 'SUCCESS') passed++
      else if (c.state === 'PENDING' || c.state === 'EXPECTED') pending++
      else failed.push({ name, url })
    } else if (c.status !== 'COMPLETED') pending++
    else if (PASSING.includes(c.conclusion ?? '')) passed++
    else failed.push({ name, url })
  }
  return { passed, pending, failed }
}

export const register: Register = on => {
  let lastState = ''
  let prTimer: { cancel: () => void } | undefined
  // Set by session.start once the session is in a git repo.
  let schedulePr: ((seconds: number) => void) | undefined

  on('session.start', async ($, e, next) => {
    const git = await $.process.run(['git', 'rev-parse', '--absolute-git-dir'])
    if (git.exitCode !== 0) {
      return next(e)
    }
    const file = `${git.stdout.trim()}/claude-pipeline/state.json`

    const pollPipeline = async () => {
      const state = await $.fs.read(file).catch(() => '')
      if (state !== lastState) {
        lastState = state
        const parsed: Pipeline | null = state ? JSON.parse(state) : null
        await update($, pipeline, () => parsed)
      }
    }

    const pollPr = async () => {
      const branch = (await $.process.run(['git', 'branch', '--show-current'])).stdout.trim()
      if (!branch || branch === 'main' || branch === 'master') {
        await update($, pr, () => null)
        return
      }
      const gh = await $.process.run(
        ['gh', 'pr', 'view', '--json', 'number,url,state,isDraft,reviewDecision,statusCheckRollup'],
        { timeoutMs: 20000 },
      )
      const before = await read($, pr)
      if (gh.exitCode !== 0) {
        await update($, pr, () => null)
        return
      }
      const raw = JSON.parse(gh.stdout)
      const now: Pr = {
        number: raw.number,
        url: raw.url,
        state: raw.state,
        isDraft: raw.isDraft,
        review: raw.reviewDecision ?? '',
        ...summarize(raw.statusCheckRollup ?? []),
      }
      await update($, pr, () => now)

      // Toast when a run settles: newly failing checks, or everything green after a run.
      const failedKey = (p: Pr | null) => p?.failed.map(c => c.name).join(', ') ?? ''
      if (now.failed.length > 0 && failedKey(now) !== failedKey(before)) {
        $.ui.toast(`PR #${now.number}: CI failed — ${failedKey(now)}`)
      } else if (before && before.pending > 0 && now.pending === 0 && now.failed.length === 0) {
        $.ui.toast(`PR #${now.number}: CI passed`)
      }
    }

    // Re-arms itself so the period follows whether checks are running.
    schedulePr = (seconds: number) => {
      prTimer?.cancel()
      prTimer = $.clock.after(seconds * 1000, () => {
        void pollPr()
          .catch(() => {})
          .then(async () => schedulePr?.((await read($, pr))?.pending ? PR_FAST : PR_SLOW))
      })
    }

    await pollPipeline().catch(() => {})
    $.clock.every(2000, () => void pollPipeline().catch(() => {}))
    schedulePr(1)

    return next(e)
  })

  // A push or PR change shows up in a few seconds instead of at the next slow poll.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const ran = await next(e)
    if (/\bgit\s+push\b|\bgh\s+pr\s+(create|ready|merge|edit)\b/.test(e.command)) {
      schedulePr?.(5)
    }
    return ran
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const p = await read($, pipeline)
    const r = await read($, pr)
    if (e.props.hasSurvey || (p === null && r === null)) {
      return next(e)
    }
    const { Box, Text, Button } = $.ui.resolve(e)

    const fixCi = (q: Pr) =>
      $.prompt.submit({
        text: [
          `CI failed on PR #${q.number} (${q.url}). Failing checks:`,
          ...q.failed.map(c => `- ${c.name}: ${c.url}`),
          'Get the failing logs (`gh run view <run-id> --log-failed`, the run id is in the URL), find the cause, fix it, run the same checks locally, and tell me before pushing.',
        ].join('\n'),
      })

    return (
      <Box flexDirection="column">
        {p && (
          <Box>
            <Text bold>{p.ticket}</Text>
            <Text dimColor> · </Text>
            {STAGES.map(([key, label], i) => {
              const s = p.stages[key] ?? 'pending'
              const sep = i === 0 ? '' : ' › '
              if (s === 'done') return <Text color="green">{`${sep}${label} ✓`}</Text>
              if (s === 'active') return <Text color="yellow" bold>{`${sep}${label} ●`}</Text>
              if (s === 'failed') return <Text color="red">{`${sep}${label} ✗`}</Text>
              return <Text dimColor>{`${sep}${label}`}</Text>
            })}
          </Box>
        )}
        {r && (
          <Box>
            <Text bold>{`PR #${r.number}`}</Text>
            {r.state === 'MERGED' && <Text color="magenta"> merged</Text>}
            {r.state === 'CLOSED' && <Text dimColor> closed</Text>}
            {r.state === 'OPEN' && r.isDraft && <Text dimColor> draft</Text>}
            <Text dimColor> · CI </Text>
            {r.failed.length > 0 && <Text color="red">{`✗ ${r.failed.map(c => c.name).join(', ')} `}</Text>}
            {r.pending > 0 && <Text color="yellow">{`● ${r.pending} running `}</Text>}
            {r.passed > 0 && <Text color="green">{`✓ ${r.passed}`}</Text>}
            {r.passed + r.pending + r.failed.length === 0 && <Text dimColor>none</Text>}
            {r.review === 'APPROVED' && <Text color="green"> · approved</Text>}
            {r.review === 'CHANGES_REQUESTED' && <Text color="red"> · changes requested</Text>}
            {r.failed.length > 0 && r.state === 'OPEN' && (
              <>
                <Text> </Text>
                <Button key="fix-ci" label="Fix CI" hotkey="f" onPress={() => fixCi(r)} />
              </>
            )}
          </Box>
        )}
      </Box>
    )
  })
}
