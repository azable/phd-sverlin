/** Stable project-template identifiers and creation contracts. */

import * as v from 'valibot';

/** Runtime contract for a server-catalogued project template identifier. */
export const projectTemplateIdSchema = v.pipe(v.string(), v.regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/));

/** Runtime contract for the template selected when creating a project. */
export const projectCreationSchema = v.strictObject({
  templateId: projectTemplateIdSchema
});

const legacyProjectCreationSchema = v.variant('mode', [
  v.strictObject({ mode: v.literal('ai') }),
  v.strictObject({ mode: v.literal('dev'), exampleId: projectTemplateIdSchema })
]);

/** Persisted creation records, including the short-lived mode-based format. */
export const recordedProjectCreationSchema = v.union([
  projectCreationSchema,
  legacyProjectCreationSchema
]);

/** Immutable template selection used for all new projects. */
export type ProjectCreation = v.InferOutput<typeof projectCreationSchema>;
/** Creation value accepted when replaying existing project timelines. */
export type RecordedProjectCreation = v.InferOutput<typeof recordedProjectCreationSchema>;
/** Serializable metadata shown when choosing a project template. */
export type ProjectTemplateSummary = {
  id: string;
  title: string;
  summary: string;
  features: string[];
};

/** Default template for an empty creation request or a legacy project. */
export const defaultProjectCreation: ProjectCreation = { templateId: 'blank' };

/** Parse an external project-creation request. */
export function parseProjectCreation(value: unknown): ProjectCreation {
  const parsed = v.safeParse(projectCreationSchema, value);
  if (!parsed.success) throw new InvalidProjectCreationError(v.summarize(parsed.issues));
  return parsed.output;
}

/** Convert persisted legacy mode metadata into the canonical template selection. */
export function normalizeRecordedProjectCreation(value?: RecordedProjectCreation): ProjectCreation {
  if (!value) return defaultProjectCreation;
  if ('templateId' in value) return value;
  return value.mode === 'dev' ? { templateId: value.exampleId } : defaultProjectCreation;
}

/** Raised when an incoming template selection is malformed. */
export class InvalidProjectCreationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidProjectCreationError';
  }
}
