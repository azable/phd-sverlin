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
import type { CompiledVisualization } from '$lib/visualization/types';

export type ChatPageState = {
  messages: ChatMessage[];
  artifact: ArtifactSyncState;
};

export type ChatActionState = ChatPageState & {
  compiledVisualization?: {
    trace: CompiledVisualization;
    seed: number;
    revision: number;
  };
};
