#!/usr/bin/env node
// comments-only.mjs <base> <head> — exit 0 when every file that changed from <base> to <head>
// differs only in comments (or formatting): a TS/JS file whose code, printed by TypeScript with
// comments removed, is the same in both. Any other change, a new or deleted file, a non-code file,
// or no TypeScript in the repo → exit 1. Run in the repo.

import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { join } from 'node:path';

const [base, head] = process.argv.slice(2);
if (!base || !head) {
  console.error('usage: comments-only.mjs <base> <head>');
  process.exit(1);
}

const git = (...args) => execFileSync('git', args, { encoding: 'utf8', maxBuffer: 64 << 20 });
const root = git('rev-parse', '--show-toplevel').trim();

let ts;
try {
  ts = createRequire(join(root, 'package.json'))('typescript');
} catch {
  process.exit(1);
}

const CODE = /\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$/;
const printer = ts.createPrinter({ removeComments: true });
const code = (path, text) =>
  printer.printFile(ts.createSourceFile(path, text, ts.ScriptTarget.Latest, false, scriptKind(path)));

function scriptKind(path) {
  if (path.endsWith('.tsx')) return ts.ScriptKind.TSX;
  if (path.endsWith('.jsx')) return ts.ScriptKind.JSX;
  if (/\.(js|mjs|cjs)$/.test(path)) return ts.ScriptKind.JS;
  return ts.ScriptKind.TS;
}

const changes = git('diff', '--name-status', '--no-renames', base, head).trim().split('\n').filter(Boolean);

for (const line of changes) {
  const [status, path] = line.split('\t');
  if (status !== 'M' || !CODE.test(path)) process.exit(1);
  if (code(path, git('show', `${base}:${path}`)) !== code(path, git('show', `${head}:${path}`))) {
    process.exit(1);
  }
}
