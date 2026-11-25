import assert from 'node:assert/strict';
import { test } from 'node:test';
import { nextReleaseTag } from './next-release-tag.mjs';

test('allocates a patch version for each merge and reuses the commit tag on retry', () => {
  const tags = ['v0.5.1', 'v0.5.0', 'v0.9.0-beta.1'];
  const first = nextReleaseTag('0.5.1', tags, []);
  assert.equal(first, 'v0.5.2');
  const second = nextReleaseTag('0.5.1', [...tags, first], []);
  assert.equal(second, 'v0.5.3');
  assert.equal(nextReleaseTag('0.5.1', [...tags, first, second], [first]), first);
});

test('allows a checked-in major or minor bump and compares versions numerically', () => {
  assert.equal(nextReleaseTag('1.0.0', ['v0.5.9', 'v0.5.11'], []), 'v1.0.0');
  assert.equal(nextReleaseTag('0.5.1', ['v0.5.9', 'v0.5.11'], []), 'v0.5.12');
  assert.throws(() => nextReleaseTag('0.5.1-beta.1', [], []), /Invalid release version/);
});
