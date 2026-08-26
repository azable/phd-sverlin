import path from 'node:path';

import { repositoryRoot } from '../src/lib/server/compiler/prepared-compiler.js';

export { repositoryRoot };
export const compileRoot = path.join(repositoryRoot, 'compile');
export const cabalConfig = path.join(repositoryRoot, '.devcontainer', 'cabal.config');
export const cabalEnvironment = {
  ...process.env,
  CABAL_DIR: path.join(repositoryRoot, '.cache', 'cabal'),
  CABAL_CONFIG: cabalConfig,
  XDG_CACHE_HOME: path.join(repositoryRoot, '.cache'),
  XDG_STATE_HOME: path.join(repositoryRoot, '.local', 'state')
};
