import { appendArtifactChange } from './store';

export { SourceArtifactBusyError } from './source-file';

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

function validateSourceArtifact(content: string) {
  if (
    !content.includes('module DSL.Main') ||
    !content.includes('example :: Choreography ()') ||
    content.length > 1_000_000
  ) {
    throw new InvalidSourceArtifactError();
  }
}
