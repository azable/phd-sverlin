import path from 'node:path';

import { repositoryRoot } from '../src/lib/server/compiler/prepared-compiler.js';

export { repositoryRoot };
export const compileRoot = path.join(repositoryRoot, 'compile');
export const stackEnvironment = { ...process.env };
