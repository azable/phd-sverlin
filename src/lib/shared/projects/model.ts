/**
 * Shared project documents, commands, projected state, and transport views.
 *
 * This module is safe in both browser and server code. Event contracts live in
 * `events/`; filesystem and network behavior belong to their respective layers.
 *
 * @packageDocumentation
 */

import * as v from 'valibot';

import {
  htmlFramesManifestSchema,
  presentationLayoutSchema,
  presentationIdSchema,
  visualizationModeSchema,
  workspaceViewSchema,
  type VisualizationMode
} from '$lib/shared/presentations';

import {
  InvalidProjectDocumentError,
  projectEventSchema,
  type EventId,
  type ProjectEvent,
  type ProjectEventOf
} from './events';
import {
  naturalSchema,
  operationIdSchema,
  positiveSchema,
  textSchema,
  visualSelectionSchema,
  type ProjectArtifact
} from './events/values';
import { projectTemplateIdSchema, type ProjectCreation } from './creation';

/** Runtime schema for a complete persisted project document. */
export const projectDocumentSchema = v.object({
  schemaVersion: v.literal(1),
  projectId: textSchema,
  events: v.pipe(v.array(projectEventSchema), v.minLength(1))
});

/** Runtime schema for compact project-selector metadata. */
export const projectSummarySchema = v.object({
  projectId: textSchema,
  title: v.string(),
  updatedAt: v.pipe(v.string(), v.isoTimestamp()),
  eventCount: naturalSchema,
  templateId: projectTemplateIdSchema,
  renderer: v.optional(visualizationModeSchema)
});

/** Runtime schema for the complete project API resource. */
export const projectResourceSchema = v.object({
  document: projectDocumentSchema,
  projects: v.array(projectSummarySchema)
});

const commandBase = { operationId: operationIdSchema, expectedHead: positiveSchema };

/** Runtime discriminated union for commands accepted by the project API. */
export const projectCommandSchema = v.variant('type', [
  v.object({ ...commandBase, type: v.literal('rename'), title: textSchema }),
  v.object({
    ...commandBase,
    type: v.literal('feedback'),
    text: v.optional(v.string()),
    focus: v.array(positiveSchema),
    selection: v.optional(visualSelectionSchema),
    presentations: v.optional(
      v.pipe(v.array(presentationIdSchema), v.minLength(1), v.maxLength(2))
    ),
    presentationCount: v.picklist([1, 2])
  }),
  v.object({ ...commandBase, type: v.literal('render'), seed: positiveSchema }),
  v.object({
    ...commandBase,
    type: v.literal('prefer'),
    presentations: v.tuple([presentationIdSchema, presentationIdSchema]),
    preferred: presentationIdSchema,
    step: naturalSchema
  }),
  v.object({
    ...commandBase,
    type: v.literal('save'),
    artifactId: textSchema,
    source: v.string(),
    presentationCount: v.picklist([1, 2])
  }),
  v.object({
    ...commandBase,
    type: v.literal('save-html'),
    artifactId: textSchema,
    manifest: htmlFramesManifestSchema
  }),
  v.object({
    ...commandBase,
    type: v.literal('restore'),
    from: positiveSchema,
    seed: positiveSchema
  })
]);

/** Persisted event-sourced project document. */
export type ProjectDocument = v.InferOutput<typeof projectDocumentSchema>;
/** Validated command accepted by the project API. */
export type ProjectCommand = v.InferOutput<typeof projectCommandSchema>;
/** Project command fields supplied by the UI before concurrency metadata is added. */
export type ProjectCommandInput = ProjectCommand extends infer Command
  ? Command extends ProjectCommand
    ? Omit<Command, 'operationId' | 'expectedHead'>
    : never
  : never;
/** Stable project identifier. */
export type ProjectId = string;
/** Stable identifier for a project artifact. */
export type ArtifactId = string;
/** Project state reconstructed from events at a specific Timeline position. */
export type ProjectSnapshot = {
  at: EventId;
  title: string;
  entryArtifactId: ArtifactId;
  creation: ProjectCreation;
  renderer: VisualizationMode;
  artifacts: Record<ArtifactId, ProjectArtifact>;
  activeRender?: ProjectEventOf<'visualization.rendered'>;
  activePresentationSet?: {
    displaySetId: string;
    presentations: Array<
      ProjectEventOf<'visualization.rendered'> | ProjectEventOf<'visualization.presented'>
    >;
  };
};

/** Authorized workspace response with the complete immutable project Timeline. */
export type WorkspaceResource = {
  schemaVersion: 1;
  projectId: ProjectId;
  document: ProjectDocument;
  view: v.InferOutput<typeof workspaceViewSchema>;
  layout: v.InferOutput<typeof presentationLayoutSchema>;
  readOnly: boolean;
  userAuthorLabel: string;
  projects: ProjectSummary[];
  study?: {
    phaseId: string;
    deadlineAt?: string;
    status: 'instructions' | 'active' | 'expired' | 'complete';
  };
};

/** Complete lossless project resource returned across the network boundary. */
export type ProjectResource = v.InferOutput<typeof projectResourceSchema>;

/** Compact project metadata used by project selectors. */
export type ProjectSummary = v.InferOutput<typeof projectSummarySchema>;

/** Result of a project command and the events it appended. */
export type ProjectCommandResult = {
  document: ProjectDocument;
  appendedEvents: ProjectEvent[];
};

/** Parse and validate a complete version-one project document. */
export function normalizeProjectV1(value: unknown): ProjectDocument {
  const parsed = v.safeParse(projectDocumentSchema, value);
  if (!parsed.success) throw new InvalidProjectDocumentError(v.summarize(parsed.issues));
  validateEventIds(parsed.output);
  return parsed.output;
}

/** Parse and validate a complete project transport resource. */
export function normalizeProjectResourceV1(value: unknown): ProjectResource {
  const parsed = v.safeParse(projectResourceSchema, value);
  if (!parsed.success) throw new InvalidProjectDocumentError(v.summarize(parsed.issues));
  validateEventIds(parsed.output.document);
  return parsed.output;
}

/** Parse and validate an incoming project command. */
export function parseProjectCommand(value: unknown): ProjectCommand {
  const parsed = v.safeParse(projectCommandSchema, value);
  if (!parsed.success) throw new InvalidProjectDocumentError(v.summarize(parsed.issues));
  return parsed.output;
}

function validateEventIds(document: ProjectDocument): void {
  document.events.forEach((event, index) => {
    if (event.id !== index + 1) {
      throw new InvalidProjectDocumentError(
        `Event ${event.id} is not at its stable 1-based position ${index + 1}.`
      );
    }
  });
  if (document.events[0].type !== 'project.created') {
    throw new InvalidProjectDocumentError('The first event must create the project.');
  }
}
