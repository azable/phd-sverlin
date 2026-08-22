import { json } from '@sveltejs/kit';

import { InvalidProjectDocumentError, type EventId } from '$lib/projects/events';
import {
  parseProjectCommand,
  type ProjectCommand,
  type ProjectCommandResult
} from '$lib/projects/model';
import { submitProjectFeedback } from '$lib/server/projects/commands';
import { ProjectConflictError, ProjectNotFoundError } from '$lib/server/projects/repository';
import {
  loadProjectView,
  renameProject,
  renderProject,
  restoreProjectArtifacts,
  updateProjectArtifact
} from '$lib/server/projects/service';

import type { RequestHandler } from './$types';

/** Load the current or historical hydrated view of a project. */
export const GET: RequestHandler = async ({ params, url }) => {
  try {
    return json(await loadProjectView(params.projectId, readCursor(url.searchParams.get('at'))));
  } catch (cause) {
    return projectError(cause);
  }
};

/** Validate and execute one optimistic-concurrency project command. */
export const POST: RequestHandler = async ({ params, request }) => {
  try {
    const command = parseProjectCommand(await request.json());
    await runCommand(params.projectId, command);
    return json(await loadProjectView(params.projectId));
  } catch (cause) {
    return projectError(cause);
  }
};

function runCommand(projectId: string, command: ProjectCommand): Promise<ProjectCommandResult> {
  const common = {
    projectId,
    expectedHead: command.expectedHead,
    operationId: command.operationId
  };
  switch (command.type) {
    case 'rename':
      return renameProject({ ...common, title: command.title });
    case 'feedback':
      return submitProjectFeedback({
        ...common,
        text: command.text,
        focus: command.focus,
        selection: command.selection,
        seed: command.seed
      });
    case 'render':
      return renderProject({ ...common, seed: command.seed });
    case 'save':
      return updateProjectArtifact({
        ...common,
        artifactId: command.artifactId,
        source: command.source,
        seed: command.seed
      });
    case 'restore':
      return restoreProjectArtifacts({ ...common, from: command.from, seed: command.seed });
  }
}

function readCursor(value: string | null): EventId | undefined {
  if (value === null) return undefined;
  const at = Number(value);
  if (!Number.isSafeInteger(at) || at < 1) throw new InvalidProjectDocumentError('Invalid cursor.');
  return at;
}

function projectError(cause: unknown) {
  if (cause instanceof ProjectNotFoundError) return json({ error: cause.message }, { status: 404 });
  if (
    cause instanceof ProjectConflictError ||
    (cause instanceof Error && cause.name === 'ProjectConflictError')
  ) {
    return json({ error: cause.message }, { status: 409 });
  }
  if (cause instanceof InvalidProjectDocumentError || cause instanceof SyntaxError) {
    return json({ error: cause.message }, { status: 400 });
  }
  return json(
    { error: cause instanceof Error ? cause.message : 'Project operation failed.' },
    { status: 422 }
  );
}
