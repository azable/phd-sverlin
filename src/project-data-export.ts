/** Command-line entry point for canonical PostgreSQL data exports. */

import path from 'node:path';

import {
  writeSelectedDataDirectory,
  type DataExportSelection
} from '$lib/server/data-export-service';
import { closeDatabase } from '$lib/server/db';

const options = parseArguments(process.argv.slice(2));
const exportedAt = new Date().toISOString();
const timestamp = exportedAt.replaceAll(':', '-');
const output = path.resolve(
  options.output ?? path.join('outputs', 'data-export', defaultLabel(options.selection), timestamp)
);

try {
  const manifest = await writeSelectedDataDirectory(output, options.selection, { exportedAt });
  console.log(`Exported ${manifest.projectCount} project(s) to ${output}`);
} finally {
  await closeDatabase();
}

function parseArguments(arguments_: string[]): {
  selection: DataExportSelection;
  output?: string;
} {
  let scope: 'projects' | 'participant' | 'study' | undefined;
  let projectId: string | undefined;
  let participantId: string | undefined;
  let studyId: string | undefined;
  let studyVersion: number | undefined;
  let output: string | undefined;
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === '--') continue;
    if (argument === '--scope') {
      const value = requiredValue(arguments_, ++index, '--scope');
      if (value !== 'projects' && value !== 'participant' && value !== 'study') {
        throw new Error('--scope must be projects, participant, or study.');
      }
      scope = value;
    } else if (argument === '--project') {
      projectId = requiredValue(arguments_, ++index, '--project');
    } else if (argument === '--participant') {
      participantId = requiredValue(arguments_, ++index, '--participant');
    } else if (argument === '--study') {
      studyId = requiredValue(arguments_, ++index, '--study');
    } else if (argument === '--version') {
      const value = Number(requiredValue(arguments_, ++index, '--version'));
      if (!Number.isSafeInteger(value) || value <= 0) {
        throw new Error('--version must be a positive integer.');
      }
      studyVersion = value;
    } else if (argument === '--output') {
      output = requiredValue(arguments_, ++index, '--output');
    } else {
      throw new Error(`Unknown data export argument: ${argument}`);
    }
  }
  if (!scope) throw new Error('--scope is required.');
  if (scope === 'projects') {
    rejectUnexpected({ participantId, studyId, studyVersion }, 'projects');
    return {
      selection: { type: 'projects', ...(projectId ? { projectId } : {}) },
      ...(output ? { output } : {})
    };
  }
  if (scope === 'participant') {
    rejectUnexpected({ projectId, studyId, studyVersion }, 'participant');
    if (!participantId) throw new Error('--participant is required for participant exports.');
    return {
      selection: {
        type: 'participant',
        participant: { type: 'participant-id', value: participantId }
      },
      ...(output ? { output } : {})
    };
  }
  rejectUnexpected({ projectId, participantId }, 'study');
  if ((studyId === undefined) !== (studyVersion === undefined)) {
    throw new Error('--study and --version must be supplied together.');
  }
  return {
    selection: { type: 'study', ...(studyId ? { studyId, studyVersion } : {}) },
    ...(output ? { output } : {})
  };
}

function rejectUnexpected(values: Record<string, unknown>, scope: string): void {
  if (Object.values(values).some((value) => value !== undefined)) {
    throw new Error(`One or more arguments do not apply to the ${scope} scope.`);
  }
}

function requiredValue(arguments_: string[], index: number, option: string): string {
  const value = arguments_[index]?.trim();
  if (!value) throw new Error(`${option} requires a value.`);
  return value;
}

function defaultLabel(selection: DataExportSelection): string {
  if (selection.type === 'projects') return selection.projectId ? 'project' : 'all-projects';
  if (selection.type === 'participant') return `participant-${selection.participant.value}`;
  return selection.studyId
    ? `study-${selection.studyId}-v${selection.studyVersion}`
    : 'all-studies';
}
