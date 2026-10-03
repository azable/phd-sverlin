/** Developer-owned project starters. */

import type { ProjectCreation, ProjectTemplateSummary } from '$lib/shared/projects/creation';
import { linearSearchSource, sverlinStarter } from '$lib/visualization-modes/sverlin/contract';

const templates = [
  {
    id: 'blank',
    title: 'Blank project',
    summary: 'Start with a small self-contained visualization component.',
    features: ['AI-assisted editing'],
    source: sverlinStarter.source
  },
  {
    id: 'linear-search',
    title: 'Linear search',
    summary: 'A stepped, seeded array search in one Svelte component.',
    features: ['steps', 'seeded input', 'Svelte'],
    source: linearSearchSource
  }
] as const;

/** Metadata offered to administrator project creation. */
export function listProjectTemplates(): ProjectTemplateSummary[] {
  return templates.map(({ source: _source, features, ...template }) => ({
    ...template,
    features: [...features]
  }));
}

/** Return a known immutable starter or a client-safe validation error. */
export function getProjectTemplate(templateId: string): (typeof templates)[number] {
  const template = templates.find(({ id }) => id === templateId);
  if (!template) throw new UnknownProjectTemplateError(templateId);
  return template;
}

export function resolveProjectTemplate(creation: ProjectCreation): {
  source: string;
  title: string;
} {
  const template = getProjectTemplate(creation.templateId);
  if (creation.renderer && creation.renderer !== 'sverlin' && creation.templateId !== 'blank') {
    throw new Error('This starter is available only for the Svelte-backed mode.');
  }
  return { source: template.source, title: template.title };
}

export class UnknownProjectTemplateError extends Error {
  constructor(templateId: string) {
    super(`Unknown project template: ${templateId}.`);
    this.name = 'UnknownProjectTemplateError';
  }
}
