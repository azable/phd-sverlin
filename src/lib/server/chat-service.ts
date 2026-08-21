import { updateArtifactFromChat, validateSourceArtifact } from '$lib/server/artifacts/service';
import { getArtifactContext } from '$lib/server/artifacts/store';
import { getChatbot } from '$lib/server/chat-bots/registry';
import type { ChatbotRequest, ChatbotResult } from '$lib/server/chat-bots/types';
import { getChatState, saveChatMessages } from '$lib/server/chat-sessions';
import type { CompileVisualizationResult } from '$lib/server/compile-visualization';
import { compileSource } from '$lib/server/compile-visualization';
import {
  compilationFailureAttempt,
  createCompilationFailureRecord,
  promptSha256,
  safelyPersistCompilationFailureRecord,
  sourceSha256,
  updateCompilationFailureRecord
} from '$lib/server/compilation-failures';
import { formatDiagnosticSummary } from '$lib/server/compiler-diagnostics';

import type { ChatActionState, ChatMessage } from '$lib/chat/types';
import type { CompileDebug, CompilerDiagnostic } from '$lib/visualization/types';

export { InvalidSourceArtifactError } from '$lib/server/artifacts/service';

export class CandidateCompilationInfrastructureError extends Error {
  readonly failureRecordId: string;

  constructor(failureRecordId: string) {
    super(`The candidate compiler failed. Failure record: ${failureRecordId}`);
    this.name = 'CandidateCompilationInfrastructureError';
    this.failureRecordId = failureRecordId;
  }
}

export async function sendChatMessage(message: string, seed: number): Promise<ChatActionState> {
  const current = getChatState();
  const artifact = getArtifactContext();
  const chatbot = getChatbot();
  const turnId = crypto.randomUUID();
  const requestMessages = [...current.messages, { role: 'user' as const, content: message }];
  const firstRequest: ChatbotRequest = { messages: requestMessages, artifact };
  const firstResult = await chatbot.generateReply(firstRequest);

  if (firstResult.sourceArtifactContent === undefined) {
    saveCompletedTurn(current.messages, message, firstResult.reply);
    return getChatState();
  }

  const firstCompile = await compileCandidate(
    firstResult.sourceArtifactContent,
    seed,
    artifact.current.path
  );
  if (firstCompile.ok) {
    return commitCompiledCandidate(
      current.messages,
      message,
      firstResult,
      firstCompile,
      artifact.headRevision,
      turnId,
      seed
    );
  }

  let failureRecord = await createCompilationFailureRecord({
    origin: { kind: 'ai-candidate', turnId, userMessage: message },
    artifact: {
      id: artifact.current.id,
      path: artifact.current.path,
      baseRevision: artifact.headRevision,
      baseContent: artifact.current.content,
      baseSha256: sourceSha256(artifact.current.content)
    },
    prompt: promptSnapshot(firstResult),
    attempts: [
      failureAttempt(1, firstResult, firstResult.sourceArtifactContent, seed, firstCompile)
    ],
    resolution: canAssistantRepair(firstCompile) ? 'retrying' : 'infrastructure-failure'
  });
  await safelyPersistCompilationFailureRecord(failureRecord);

  if (!canAssistantRepair(firstCompile)) {
    throw new CandidateCompilationInfrastructureError(failureRecord.recordId);
  }

  const retryRequest: ChatbotRequest = {
    messages: requestMessages,
    artifact,
    compilationFeedback: {
      attempt: 1,
      failureRecordId: failureRecord.recordId,
      failedSource: firstResult.sourceArtifactContent,
      assistantReply: firstResult.reply,
      diagnostics: firstCompile.diagnostics
    }
  };
  let retryResult: ChatbotResult;
  try {
    retryResult = await chatbot.generateReply(retryRequest);
  } catch (error) {
    failureRecord = updateCompilationFailureRecord(failureRecord, {
      resolution: 'infrastructure-failure'
    });
    await safelyPersistCompilationFailureRecord(failureRecord);
    throw error;
  }
  failureRecord = updateCompilationFailureRecord(failureRecord, {
    repairPrompt: promptSnapshot(retryResult),
    resolution: 'retrying'
  });
  await safelyPersistCompilationFailureRecord(failureRecord);

  if (retryResult.sourceArtifactContent === undefined) {
    failureRecord = updateCompilationFailureRecord(failureRecord, { resolution: 'rejected' });
    await safelyPersistCompilationFailureRecord(failureRecord);
    saveCompletedTurn(
      current.messages,
      message,
      rejectedCandidateReply(firstCompile.diagnostics, failureRecord.recordId)
    );
    return getChatState();
  }

  const retryCompile = await compileCandidate(
    retryResult.sourceArtifactContent,
    seed,
    artifact.current.path
  );
  if (!retryCompile.ok) {
    failureRecord = updateCompilationFailureRecord(failureRecord, {
      attempt: failureAttempt(
        2,
        retryResult,
        retryResult.sourceArtifactContent,
        seed,
        retryCompile
      ),
      resolution: canAssistantRepair(retryCompile) ? 'rejected' : 'infrastructure-failure'
    });
    await safelyPersistCompilationFailureRecord(failureRecord);

    if (!canAssistantRepair(retryCompile)) {
      throw new CandidateCompilationInfrastructureError(failureRecord.recordId);
    }

    saveCompletedTurn(
      current.messages,
      message,
      rejectedCandidateReply(retryCompile.diagnostics, failureRecord.recordId)
    );
    return getChatState();
  }

  failureRecord = updateCompilationFailureRecord(failureRecord, { resolution: 'recovered' });
  await safelyPersistCompilationFailureRecord(failureRecord);

  return commitCompiledCandidate(
    current.messages,
    message,
    retryResult,
    retryCompile,
    artifact.headRevision,
    turnId,
    seed
  );
}

async function compileCandidate(content: string, seed: number, sourceLabel: string) {
  try {
    validateSourceArtifact(content);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return invalidCandidateResult(message);
  }

  return compileSource({
    sourceContent: content,
    sourceLabel,
    seed,
    owner: 'ai-candidate'
  });
}

function commitCompiledCandidate(
  previousMessages: ChatMessage[],
  message: string,
  result: ChatbotResult,
  compile: Extract<CompileVisualizationResult, { ok: true }>,
  baseRevision: number,
  turnId: string,
  seed: number
): ChatActionState {
  if (result.sourceArtifactContent === undefined) {
    throw new Error('A compiled chatbot candidate has no source.');
  }

  const artifactState = updateArtifactFromChat(result.sourceArtifactContent, baseRevision, turnId);
  saveCompletedTurn(previousMessages, message, result.reply);

  return {
    ...getChatState(),
    compiledVisualization: {
      trace: compile.trace,
      seed,
      revision: artifactState.headRevision
    }
  };
}

function saveCompletedTurn(previousMessages: ChatMessage[], message: string, reply: string) {
  saveChatMessages([
    ...previousMessages,
    { role: 'user', content: message },
    { role: 'assistant', content: reply }
  ]);
}

function canAssistantRepair(result: Extract<CompileVisualizationResult, { ok: false }>) {
  return result.failureKind === 'source' || result.failureKind === 'pipeline';
}

function failureAttempt(
  attempt: number,
  result: ChatbotResult,
  candidateContent: string,
  seed: number,
  compile: Extract<CompileVisualizationResult, { ok: false }>
) {
  return compilationFailureAttempt({
    attempt,
    candidateContent,
    seed,
    debug: compile.debug,
    failureKind: compile.failureKind ?? 'pipeline',
    diagnostics: compile.diagnostics,
    assistant: {
      reply: result.reply,
      ...result.generation
    }
  });
}

function promptSnapshot(result: ChatbotResult) {
  const prompt = {
    botId: result.generation.botId,
    ...result.prompt
  };

  return { ...prompt, sha256: promptSha256(prompt) };
}

function rejectedCandidateReply(diagnostics: CompilerDiagnostic[], failureRecordId: string) {
  return `I could not apply this change because the corrected source still failed compilation. The previous source and visualization are unchanged.\n\n${formatDiagnosticSummary(diagnostics)}\n\nFailure record: ${failureRecordId}`;
}

function invalidCandidateResult(
  message: string
): Extract<CompileVisualizationResult, { ok: false }> {
  const debug: CompileDebug = {
    command: 'candidate-validation',
    args: [],
    cwd: process.cwd(),
    durationMs: 0,
    exitCode: null,
    stdout: '',
    stderr: message
  };

  return {
    ok: false,
    error: message,
    debug,
    status: 422,
    diagnostics: [{ severity: 'error', message, raw: message }],
    failureKind: 'source'
  };
}
