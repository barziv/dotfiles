import { expect, mock, test } from 'claude-code/testing'

const STATE = JSON.stringify({
  ticket: 'INT-7',
  stages: { plan: 'done', 'plan-review': 'done', 'plan-you': 'active', code: 'pending' },
})

test('band shows the ticket and each stage', async ($, on) => {
  on('process.run', () => ({ value: { exitCode: 0, stdout: '/repo/.git/worktrees/x\n', stderr: '' } }))
  on('fs.read', () => ({ value: STATE }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: '/repo/x', surface: 'terminal', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({
      plugin: 'ticket-pipeline',
      component: 'AbovePrompt',
      surface,
      props: { hasSurvey: false },
    })
    expect((await band.find({ type: 'Text', text: /INT-7/ }))?.text).toBe('INT-7')
    expect((await band.find({ type: 'Text', text: /review/ }))?.text).toBe(' › review ✓')
    expect((await band.find({ type: 'Text', text: /you ●/ }))?.text).toBe(' › you ●')
    expect((await band.find({ type: 'Text', text: /CR/ }))?.text).toBe(' › CR')
    await band.unmount()
  }
})

test('no pipeline, no band', async ($, on) => {
  on('process.run', () => ({ value: { exitCode: 128, stdout: '', stderr: 'not a git repo' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })

  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  const band = await $.ui.mount({
    plugin: 'ticket-pipeline',
    component: 'AbovePrompt',
    surface: 'terminal',
    props: { hasSurvey: false },
  })
  expect((await band.find({ type: 'Text', text: /engine/ }))?.text).toBe('engine')
  await band.unmount()
})

const PR_JSON = JSON.stringify({
  number: 42,
  url: 'https://github.com/o/r/pull/42',
  state: 'OPEN',
  isDraft: false,
  reviewDecision: 'APPROVED',
  statusCheckRollup: [
    { __typename: 'CheckRun', name: 'lint', status: 'COMPLETED', conclusion: 'FAILURE', detailsUrl: 'https://x/runs/1/job/2' },
    { __typename: 'CheckRun', name: 'test', status: 'IN_PROGRESS', conclusion: '' },
    { __typename: 'CheckRun', name: 'build', status: 'COMPLETED', conclusion: 'SUCCESS' },
    { __typename: 'StatusContext', context: 'vercel', state: 'SUCCESS' },
  ],
})

test('PR row shows checks, toasts the failure, and Fix CI asks Claude', async ($, on) => {
  const clock = mock.clock(on)
  const submitted: string[] = []
  const toasts: string[] = []
  on('process.run', (_, e) => {
    const cmd = e.argv.join(' ')
    if (cmd.startsWith('git rev-parse')) return { value: { exitCode: 0, stdout: '/repo/.git\n', stderr: '' } }
    if (cmd.startsWith('git branch')) return { value: { exitCode: 0, stdout: 'barz/feat/x\n', stderr: '' } }
    return { value: { exitCode: 0, stdout: PR_JSON, stderr: '' } }
  })
  on('fs.read', () => {
    throw new Error('missing')
  })
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)
    return { drop: 'test' }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  await clock.advance(1500)

  const band = await $.ui.mount({
    plugin: 'ticket-pipeline',
    component: 'AbovePrompt',
    surface: 'terminal',
    props: { hasSurvey: false },
  })
  expect((await band.find({ type: 'Text', text: /PR #/ }))?.text).toBe('PR #42')
  expect((await band.find({ type: 'Text', text: /✗/ }))?.text).toBe('✗ lint ')
  expect((await band.find({ type: 'Text', text: /running/ }))?.text).toBe('● 1 running ')
  expect((await band.find({ type: 'Text', text: /✓/ }))?.text).toBe('✓ 2')
  expect(toasts).toEqual(['PR #42: CI failed — lint'])

  await band.press({ key: 'fix-ci' })
  expect(submitted[0]).toContain('- lint: https://x/runs/1/job/2')
  await band.unmount()
})
