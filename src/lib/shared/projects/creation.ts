/** Stable project-template identifiers and creation contracts. */

import * as v from 'valibot';

import { visualizationModeSchema, type VisualizationMode } from '$lib/shared/presentations';

/** Runtime contract for a server-catalogued project template identifier. */
export const projectTemplateIdSchema = v.pipe(v.string(), v.regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/));

/** Runtime contract for the template selected when creating a project. */
export const projectCreationSchema = v.strictObject({
  templateId: projectTemplateIdSchema,
  renderer: v.optional(visualizationModeSchema)
});

/** Immutable template selection used for all new projects. */
export type ProjectCreation = v.InferOutput<typeof projectCreationSchema>;
/** Serializable metadata shown when choosing a project template. */
export type ProjectTemplateSummary = {
  id: string;
  title: string;
  summary: string;
  features: string[];
};

/** Default template for an empty creation request. */
export const defaultProjectCreation: ProjectCreation = { templateId: 'blank', renderer: 'sverlin' };

/** Renderer selected by a new or historical project creation record. */
export function projectCreationRenderer(creation: ProjectCreation): VisualizationMode {
  return creation.renderer ?? 'sverlin';
}

/** Parse an external project-creation request. */
export function parseProjectCreation(value: unknown): ProjectCreation {
  const parsed = v.safeParse(projectCreationSchema, value);
  if (!parsed.success) throw new InvalidProjectCreationError(v.summarize(parsed.issues));
  return parsed.output;
}

/** Raised when an incoming template selection is malformed. */
export class InvalidProjectCreationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidProjectCreationError';
  }
}
