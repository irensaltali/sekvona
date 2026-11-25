import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const stableTag = /^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

function parts(tag) {
  return tag.slice(1).split('.').map(BigInt);
}

function compareTags(a, b) {
  const right = parts(b);
  const difference = parts(a).map((value, index) => value - right[index]).find(value => value !== 0n);
  return difference === undefined ? 0 : difference > 0n ? 1 : -1;
}

export function nextReleaseTag(version, tags, commitTags) {
  const declared = `v${version}`;
  if (!stableTag.test(declared)) throw new Error(`Invalid release version: ${version}`);

  const existing = commitTags.filter(tag => stableTag.test(tag)).sort(compareTags).at(-1);
  if (existing) return existing;

  const latest = tags.filter(tag => stableTag.test(tag)).sort(compareTags).at(-1);
  if (!latest || compareTags(declared, latest) > 0) return declared;

  const [major, minor, patch] = parts(latest);
  return `v${major}.${minor}.${patch + 1n}`;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const gitTags = (...args) => execFileSync('git', ['tag', ...args], { encoding: 'utf8' }).trim().split('\n');
  const { version } = JSON.parse(readFileSync('apps/desktop/package.json', 'utf8'));
  console.log(nextReleaseTag(version, gitTags('--list'), gitTags('--points-at', 'HEAD')));
}
