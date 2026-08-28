#!/usr/bin/env node

const baseUrl = normalizeUrl(process.env.SVERLIN_SMOKE_URL ?? process.argv[2]);
const expectedBuild = process.env.SVERLIN_SMOKE_BUILD_SHA?.trim();

if (!baseUrl) {
  console.error('Usage: SVERLIN_SMOKE_URL=https://... pnpm run smoke:deployment');
  process.exit(64);
}

const live = await requestJson('/api/health/live');
assert(live.response.ok && live.value.status === 'ok', 'Liveness check failed.');

const ready = await requestJson('/api/health/ready');
assert(ready.response.ok && ready.value.status === 'ready', 'Readiness check failed.');

const version = await requestJson('/api/version');
assert(version.response.ok, 'Version check failed.');
if (expectedBuild) {
  assert(
    version.value.buildSha === expectedBuild,
    `Expected build ${expectedBuild}, received ${String(version.value.buildSha)}.`
  );
}

console.log(
  JSON.stringify(
    {
      ok: true,
      url: baseUrl,
      version: version.value.version,
      buildSha: version.value.buildSha,
      compilerSourceSha256: version.value.compilerSourceSha256
    },
    null,
    2
  )
);

async function requestJson(pathname, init) {
  const response = await fetch(`${baseUrl}${pathname}`, init);
  let value;
  try {
    value = await response.json();
  } catch {
    throw new Error(`${pathname} did not return JSON (HTTP ${response.status}).`);
  }
  return { response, value };
}

function normalizeUrl(value) {
  return value?.trim().replace(/\/$/, '');
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
