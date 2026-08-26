#!/usr/bin/env node

import {
  clearMaintenanceLock,
  readMaintenanceStatus,
  writeMaintenanceLock
} from '../src/lib/server/maintenance-lock.js';

const [command = 'status', ...rawWords] = process.argv.slice(2);
const words = rawWords[0] === '--' ? rawWords.slice(1) : rawWords;

switch (command) {
  case 'lock':
    print(await writeMaintenanceLock(words.join(' ') || 'Application maintenance in progress.'));
    break;
  case 'unlock':
    print(await clearMaintenanceLock());
    break;
  case 'status':
    print(await readMaintenanceStatus());
    break;
  default:
    console.error('Usage: app-lock.mjs <lock [reason...]|unlock|status>');
    process.exitCode = 2;
}

function print(status) {
  console.log(JSON.stringify(status, null, 2));
}
