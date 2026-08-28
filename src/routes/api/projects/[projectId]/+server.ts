import { json } from '@sveltejs/kit';

import { InvalidProjectDocumentError } from '$lib/shared/projects/events';
import {
  parseProjectCommand,
  type ProjectCommand,
  type ProjectCommandResult
} from '$lib/shared/projects/model';
import { submitProjectFeedback } from '$lib/server/projects/commands';
import {
  projectCommandOwner,
  projectListOwner,
  requireProjectAccess
} from '$lib/server/authorization';
import { createProjectJob } from '$lib/server/projects/jobs';
import { ProjectConflictError, ProjectNotFoundError } from '$lib/server/projects/repository';
import { usesPostgresProjectStore } from '$lib/server/projects/repository';
import {
  loadProjectResource,
  renameProject,
  renderProject,
  restoreProjectArtifacts,
  updateProjectArtifact
} from '$lib/server/projects/service';

import type { RequestHandler } from './$types';

/** Load the complete project resource; historical views are projected by consumers. */
export const GET: RequestHandler = async ({ params, locals }) => {
  try {
    const principal = await requireProjectAccess(locals, params.projectId);
    return json(await loadProjectResource(params.projectId, projectListOwner(principal)));
  } catch (cause) {
    return projectError(cause);
  }
};

/** Validate and execute one optimistic-concurrency project command. */
export const POST: RequestHandler = async ({ params, request, locals }) => {
  try {
    const principal = await requireProjectAccess(locals, params.projectId);
    const command = parseProjectCommand(await request.json());
    if (usesPostgresProjectStore) {
      const job = await createProjectJob({
        projectId: params.projectId,
        ownerUserId: await projectCommandOwner(principal, params.projectId),
        operationId: command.operationId,
        expectedHead: command.expectedHead,
        command
      });
      return json(
        { projectId: params.projectId, jobId: job.id, status: job.status },
        { status: 202 }
      );
    }
    await runCommand(params.projectId, command);
    return json(await loadProjectResource(params.projectId, projectListOwner(principal)));
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
