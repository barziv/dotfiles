#!/usr/bin/env node
// Usage: t3-delete-subagents.mjs [<parent-thread-id>] [--dry-run]
// Deletes the finished subagent threads of a T3 Code thread (default: $T3CODE_THREAD_ID).
//
// T3 refuses to restore files on rewind while any other thread shares the worktree, and a
// subagent thread inherits its parent's worktree. Archiving doesn't help (archived threads still
// count); only deleted ones are skipped. Neither the T3 MCP tools nor the `t3` CLI can delete a
// thread, so this sends `thread.delete` over the app's own WebSocket RPC with a short-lived token.
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const parentId = args.find((arg) => !arg.startsWith('--')) ?? process.env.T3CODE_THREAD_ID;

if (!parentId) {
  console.error('No thread id: pass one or run inside a T3 Code thread.');
  process.exit(1);
}

const userdata = join(homedir(), '.t3', 'userdata');
const db = new DatabaseSync(join(userdata, 'statev2.sqlite'), { readOnly: true });
const children = db
  .prepare(
    `SELECT s.child_thread_id AS id, t.title, s.status
       FROM orchestration_v2_projection_subagents s
       JOIN orchestration_v2_projection_threads t ON t.thread_id = s.child_thread_id
      WHERE s.thread_id = ? AND t.deleted_at IS NULL`
  )
  .all(parentId);
db.close();

const finished = children.filter((child) => child.status !== 'running' && child.status !== 'pending');
for (const child of children.filter((child) => !finished.includes(child))) {
  console.log(`skip (${child.status}): ${child.title}`);
}
if (finished.length === 0) {
  console.log('No finished subagent threads to delete.');
  process.exit(0);
}
if (dryRun) {
  for (const child of finished) console.log(`would delete: ${child.title}`);
  process.exit(0);
}

const { origin } = JSON.parse(readFileSync(join(userdata, 'server-runtime.json'), 'utf8'));
const token = execFileSync(
  't3',
  ['auth', 'session', 'issue', '--scope', 'orchestration:operate', '--ttl', '5m',
    '--label', 'delete-subagents', '--token-only'],
  { encoding: 'utf8' }
).trim();
const ticketResponse = await fetch(`${origin}/api/auth/websocket-ticket/rpc`, {
  method: 'POST',
  headers: { authorization: `Bearer ${token}` },
});
if (!ticketResponse.ok) {
  console.error(`WebSocket ticket request failed: ${ticketResponse.status} ${await ticketResponse.text()}`);
  process.exit(1);
}
const { ticket } = await ticketResponse.json();

const wsUrl = new URL('/ws', origin.replace(/^http/, 'ws'));
wsUrl.searchParams.set('orchestrationProtocol', '2');
wsUrl.searchParams.set('wsTicket', ticket);
const socket = new WebSocket(wsUrl);
const pending = new Map();

socket.addEventListener('message', (event) => {
  for (const line of String(event.data).split('\n').filter(Boolean)) {
    const message = JSON.parse(line);
    if (message._tag === 'Ping') socket.send(JSON.stringify({ _tag: 'Pong' }));
    if (message._tag === 'Exit' && pending.has(message.requestId)) {
      pending.get(message.requestId)(message.exit);
      pending.delete(message.requestId);
    }
  }
});
await new Promise((resolve, reject) => {
  socket.addEventListener('open', resolve, { once: true });
  socket.addEventListener('error', reject, { once: true });
});

let failed = 0;
for (const [index, child] of finished.entries()) {
  const requestId = String(index + 1);
  const exit = await new Promise((resolve) => {
    pending.set(requestId, resolve);
    socket.send(JSON.stringify({
      _tag: 'Request',
      id: requestId,
      tag: 'orchestration.dispatchCommand',
      payload: { type: 'thread.delete', commandId: randomUUID(), threadId: child.id },
      headers: [],
    }));
  });
  if (exit._tag === 'Success') {
    console.log(`deleted: ${child.title}`);
  } else {
    failed += 1;
    console.error(`failed: ${child.title}: ${JSON.stringify(exit.cause)}`);
  }
}
socket.close();
process.exit(failed === 0 ? 0 : 1);
