import { appendArtifactChange } from './store';

export class InvalidSourceArtifactError extends Error {
  constructor() {
    super('The chatbot returned an invalid DSL source artifact.');
    this.name = 'InvalidSourceArtifactError';
  }
}

export function updateArtifactFromChat(content: string, baseRevision: number, turnId: string) {
  validateSourceArtifact(content);
  return appendArtifactChange(content, baseRevision, { kind: 'chat', turnId }, turnId);
}

export function updateArtifactFromManualEdit(
  content: string,
  baseRevision: number,
  reason?: string
) {
  validateSourceArtifact(content);
  return appendArtifactChange(
    content,
    baseRevision,
    { kind: 'manual', actor: 'user', reason },
    crypto.randomUUID()
  );
}

export function validateSourceArtifact(content: string) {
  // Syntax and the required declarations are checked by the Haskell
  // elaboration/interpretation boundary so its diagnostics remain canonical.
  if (content.includes('\0') || content.length > 1_000_000) {
    throw new InvalidSourceArtifactError();
  }
}
