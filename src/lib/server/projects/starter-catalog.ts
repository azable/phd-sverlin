/** Validated, server-owned source starters for project creation. */

import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import * as v from 'valibot';

import catalogValue from '../../../../examples/catalog.json';

import {
  defaultProjectCreation,
  projectTemplateIdSchema,
  type ProjectCreation,
  type ProjectTemplateSummary
} from '$lib/shared/projects/creation';

const fileNameSchema = v.pipe(v.string(), v.regex(/^[A-Za-z][A-Za-z0-9]*\.sverlin$/));
const exampleSchema = v.strictObject({
  id: projectTemplateIdSchema,
  file: fileNameSchema,
  title: v.pipe(v.string(), v.nonEmpty()),
  summary: v.pipe(v.string(), v.nonEmpty()),
  features: v.pipe(v.array(v.pipe(v.string(), v.nonEmpty())), v.minLength(1))
});
const catalogSchema = v.strictObject({
  version: v.literal(1),
  templates: v.pipe(v.array(exampleSchema), v.minLength(1))
});

const examplesDirectory = path.resolve(
  process.env.SVERLIN_REPOSITORY_ROOT?.trim() || process.cwd(),
  'examples'
);
const sourcesByFile = new Map(
  readdirSync(examplesDirectory)
    .filter((fileName) => fileName.endsWith('.sverlin'))
    .map((fileName) => [fileName, readFileSync(path.join(examplesDirectory, fileName), 'utf8')])
);
const parsedCatalog = v.safeParse(catalogSchema, catalogValue);
if (!parsedCatalog.success) {
  throw new Error(`Invalid example catalog: ${v.summarize(parsedCatalog.issues)}`);
}
const catalog = parsedCatalog.output;
validateCatalogFiles();
const templatesById = new Map(catalog.templates.map((template) => [template.id, template]));
if (!templatesById.has(defaultProjectCreation.templateId)) {
  throw new Error(`The default project template ${defaultProjectCreation.templateId} is missing.`);
}

/** Project-template metadata paired with its exact bundled source. */
type ProjectTemplate = (typeof catalog.templates)[number] & { source: string };

/** Return catalogued templates in their authored display order. */
export function listProjectTemplates(): ProjectTemplateSummary[] {
  return catalog.templates.map(({ file: _file, ...template }) => ({
    ...template,
    features: [...template.features]
  }));
}

/** Resolve one selectable template or raise a client-safe validation error. */
export function getProjectTemplate(templateId: string): ProjectTemplate {
  const template = templatesById.get(templateId);
  if (!template) throw new UnknownProjectTemplateError(templateId);
  return { ...template, features: [...template.features], source: sourceFor(template.file) };
}

/** Resolve an immutable template without exposing arbitrary source input. */
export function resolveProjectTemplate(creation: ProjectCreation): {
  source: string;
  title: string;
} {
  const template = getProjectTemplate(creation.templateId);
  return { source: template.source, title: template.title };
}

/** Raised when a creation request references no server-catalogued template. */
export class UnknownProjectTemplateError extends Error {
  constructor(templateId: string) {
    super(`Unknown project template: ${templateId}.`);
    this.name = 'UnknownProjectTemplateError';
  }
}

function sourceFor(fileName: string): string {
  const source = sourcesByFile.get(fileName);
  if (source === undefined) throw new Error(`Example source is missing: ${fileName}.`);
  return source;
}

function validateCatalogFiles(): void {
  const referenced = catalog.templates.map(({ file }) => file);
  if (new Set(referenced).size !== referenced.length) {
    throw new Error('The example catalog contains duplicate source files.');
  }
  const ids = catalog.templates.map(({ id }) => id);
  if (new Set(ids).size !== ids.length)
    throw new Error('The example catalog contains duplicate IDs.');
  for (const file of referenced) sourceFor(file);
  const orphans = [...sourcesByFile.keys()].filter((file) => !referenced.includes(file));
  if (orphans.length > 0) {
    throw new Error(`Uncatalogued Sverlin example files: ${orphans.sort().join(', ')}.`);
  }
}
