import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

import type { ArtifactChangeSource, SourceArtifact } from '$lib/artifacts/types';
import type { ChatMessage } from '$lib/chat/types';
import type { ChatBotParameters, ChatResponseFormat } from '$lib/server/chat-bots/types';
import type {
  CompileDebug,
  CompileFailureKind,
  CompilerDiagnostic
} from '$lib/visualization/types';

import { ensureWorkspaceOutputDir } from './workspace-output.js';

export type CompilationFailureAttempt = {
  attempt: number;
  candidate: {
    content: string;
    sha256: string;
  };
  assistant?: {
    reply: string;
    botId: string;
    adapterId: string;
    model?: string;
    responseId?: string;
  };
  compile: {
    seed: number;
    durationMs: number;
    exitCode: number | null;
    timedOut: boolean;
    failureKind: CompileFailureKind;
    diagnostics: CompilerDiagnostic[];
    stdout: string;
    stderr: string;
    error?: string;
  };
};

export type CompilationPromptSnapshot = {
  botId: string;
  initialPrompt: string;
  messages: ChatMessage[];
  context: unknown;
  parameters: ChatBotParameters;
  responseFormat: ChatResponseFormat;
  sha256: string;
};

export type CompilationFailureRecordV1 = {
  schemaVersion: 1;
  recordId: string;
  createdAt: string;
  updatedAt: string;
  origin:
    | {
        kind: 'ai-candidate';
        turnId: string;
        userMessage: string;
      }
    | {
        kind: 'web-compilation';
        artifactSource?: ArtifactChangeSource;
      };
  artifact: {
    id: SourceArtifact['id'];
    path: SourceArtifact['path'];
    baseRevision: number;
    baseContent: string;
    baseSha256: string;
  };
  prompt?: CompilationPromptSnapshot;
  repairPrompt?: CompilationPromptSnapshot;
  dslApiSha256?: string;
  attempts: CompilationFailureAttempt[];
  resolution: 'retrying' | 'recovered' | 'rejected' | 'unresolved' | 'infrastructure-failure';
};

type NewFailureRecord = Omit<
  CompilationFailureRecordV1,
  'schemaVersion' | 'recordId' | 'createdAt' | 'updatedAt' | 'dslApiSha256'
>;

const dslSourcePaths = ['compile/src/LinearTrace/Choreography.hs', 'compile/app/Sverlin/Source.hs'];
let dslApiFingerprint: Promise<string | undefined> | undefined;

export async function createCompilationFailureRecord(
  record: NewFailureRecord
): Promise<CompilationFailureRecordV1> {
  const now = new Date().toISOString();

  return {
    schemaVersion: 1,
    recordId: randomUUID(),
    createdAt: now,
    updatedAt: now,
    ...record,
    dslApiSha256: await readDslApiFingerprint()
  };
}

export function compilationFailureAttempt(options: {
  attempt: number;
  candidateContent: string;
  seed: number;
  debug: CompileDebug;
  failureKind: CompileFailureKind;
  diagnostics: CompilerDiagnostic[];
  assistant?: CompilationFailureAttempt['assistant'];
}): CompilationFailureAttempt {
  return {
    attempt: options.attempt,
    candidate: {
      content: options.candidateContent,
      sha256: sha256(options.candidateContent)
    },
    ...(options.assistant ? { assistant: options.assistant } : {}),
    compile: {
      seed: options.seed,
      durationMs: options.debug.durationMs,
      exitCode: options.debug.exitCode,
      timedOut: options.debug.timedOut ?? false,
      failureKind: options.failureKind,
      diagnostics: options.diagnostics,
      stdout: options.debug.stdout,
      stderr: options.debug.stderr,
      ...(options.debug.error ? { error: options.debug.error } : {})
    }
  };
}

export function updateCompilationFailureRecord(
  record: CompilationFailureRecordV1,
  update: {
    attempt?: CompilationFailureAttempt;
    repairPrompt?: CompilationFailureRecordV1['repairPrompt'];
    resolution: CompilationFailureRecordV1['resolution'];
  }
): CompilationFailureRecordV1 {
  return {
    ...record,
    updatedAt: new Date().toISOString(),
    attempts: update.attempt ? [...record.attempts, update.attempt] : record.attempts,
    ...(update.repairPrompt ? { repairPrompt: update.repairPrompt } : {}),
    resolution: update.resolution
  };
}

export async function persistCompilationFailureRecord(record: CompilationFailureRecordV1) {
  const outputRoot = await ensureWorkspaceOutputDir();
  const directory = path.join(outputRoot, 'compilation-errors');
  const destination = path.join(directory, `${record.recordId}.json`);
  const temporary = path.join(directory, `.${record.recordId}.${randomUUID()}.tmp`);

  await mkdir(directory, { recursive: true });

  try {
    await writeFile(temporary, `${JSON.stringify(record, null, 2)}\n`, {
      encoding: 'utf8',
      flag: 'wx'
    });
    await rename(temporary, destination);
  } finally {
    await rm(temporary, { force: true });
  }

  return destination;
}

export async function safelyPersistCompilationFailureRecord(record: CompilationFailureRecordV1) {
  try {
    await persistCompilationFailureRecord(record);
  } catch (error) {
    console.error(`Could not write compilation failure record ${record.recordId}.`, error);
  }
}

export function sourceSha256(content: string) {
  return sha256(content);
}

export function promptSha256(prompt: Omit<CompilationPromptSnapshot, 'sha256'>) {
  return sha256(JSON.stringify(prompt));
}

async function readDslApiFingerprint() {
  if (!dslApiFingerprint) {
    dslApiFingerprint = computeDslApiFingerprint().catch((error) => {
      console.error('Could not fingerprint the Sverlin DSL API.', error);
      return undefined;
    });
  }

  return dslApiFingerprint;
}

async function computeDslApiFingerprint() {
  const choreographyDirectory = path.resolve(process.cwd(), 'compile/src/LinearTrace/Choreography');
  const choreographyModules = (await readdir(choreographyDirectory))
    .filter((file) => file.endsWith('.hs'))
    .sort()
    .map((file) => path.join('compile/src/LinearTrace/Choreography', file));
  const sourcePaths = [...dslSourcePaths, ...choreographyModules];
  const contents = await Promise.all(
    sourcePaths.map(async (sourcePath) => {
      const content = await readFile(path.resolve(process.cwd(), sourcePath), 'utf8');
      return `${sourcePath}\0${content}`;
    })
  );

  return sha256(contents.join('\0'));
}

function sha256(value: string) {
  return createHash('sha256').update(value).digest('hex');
}
