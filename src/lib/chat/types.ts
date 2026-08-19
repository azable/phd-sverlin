export type ChatMessage = {
  role: 'user' | 'assistant';
  content: string;
};

export type {
  ArtifactChangeEvent,
  ArtifactChangeSource,
  ArtifactContext,
  ArtifactSyncState,
  JsonPatchOperation,
  SourceArtifact
} from '$lib/artifacts/types';

import type { ArtifactSyncState } from '$lib/artifacts/types';

export type ChatPageState = {
  messages: ChatMessage[];
  artifact: ArtifactSyncState;
};
