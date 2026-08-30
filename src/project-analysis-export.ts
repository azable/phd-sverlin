/** Command-line entry point for PostgreSQL project analysis exports. */

import path from 'node:path';

import { closeDatabase } from '$lib/server/db';
import { writeAnalysisDirectory } from '$lib/server/analysis-export';

const options = parseArguments(process.argv.slice(2));
const timestamp = new Date().toISOString().replaceAll(':', '-');
const output = path.resolve(options.output ?? path.join('outputs', 'project-analysis', timestamp));

try {
  const manifest = await writeAnalysisDirectory(output, options.projectId);
  console.log(`Exported ${manifest.projectCount} project(s) to ${output}`);
} finally {
  await closeDatabase();
}

function parseArguments(arguments_: string[]): { projectId?: string; output?: string } {
  const parsed: { projectId?: string; output?: string } = {};
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === '--') {
      continue;
    } else if (argument === '--project') {
      parsed.projectId = requiredValue(arguments_, ++index, '--project');
    } else if (argument === '--output') {
      parsed.output = requiredValue(arguments_, ++index, '--output');
    } else {
      throw new Error(`Unknown analysis export argument: ${argument}`);
    }
  }
  return parsed;
}

function requiredValue(arguments_: string[], index: number, option: string): string {
  const value = arguments_[index]?.trim();
  if (!value) throw new Error(`${option} requires a value.`);
  return value;
}
