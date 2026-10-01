import { randomInt } from 'node:crypto';

import { dev } from '$app/environment';
import { error, json } from '@sveltejs/kit';
import * as v from 'valibot';

import { requireAdmin } from '$lib/server/authorization';
import { visualizationService } from '$lib/server/compiler';
import {
  getProjectTemplate,
  UnknownProjectTemplateError
} from '$lib/server/projects/starter-catalog';
import { positiveSchema } from '$lib/shared/projects/events/values';

import type { RequestHandler } from './$types';

const previewRequestSchema = v.strictObject({
  exampleId: v.string(),
  // Match the compiler's generated seed range in compile/app/Main.hs.
  seed: v.optional(v.pipe(positiveSchema, v.maxValue(2147483646)))
});

/** Compile one current catalogued file without creating a project or Timeline. */
export const POST: RequestHandler = async ({ locals, request }) => {
  if (!dev) error(404, 'Example previews are available in development only.');
  requireAdmin(locals);

  let input;
  try {
    const parsed = v.safeParse(previewRequestSchema, await request.json());
    if (!parsed.success) return json({ error: v.summarize(parsed.issues) }, { status: 400 });
    input = parsed.output;
  } catch {
    return json({ error: 'Expected a JSON example preview request.' }, { status: 400 });
  }
  if (input.exampleId === 'blank') {
    return json({ error: 'The blank starter is not a visualization example.' }, { status: 400 });
  }

  let template;
  try {
    template = getProjectTemplate(input.exampleId);
  } catch (cause) {
    if (cause instanceof UnknownProjectTemplateError) {
      return json({ error: cause.message }, { status: 400 });
    }
    throw cause;
  }

  const seed = input.seed ?? randomInt(1, 2147483647);
  const result = await visualizationService.generate({
    source: { name: template.file, content: template.source },
    seed,
    signal: request.signal
  });
  if (!result.ok) {
    return json(
      { error: result.diagnostics[0]?.message ?? result.error, diagnostics: result.diagnostics },
      {
        status:
          result.failureKind === 'timeout'
            ? 504
            : result.failureKind === 'infrastructure'
              ? 503
              : 422
      }
    );
  }

  const usedFonts = new Set(
    result.visualization.elements.flatMap((element) => {
      const content = element.content;
      return content?.kind === 'plainTextContent' || content?.kind === 'codeTextContent'
        ? [content.textLayout.layoutFont.instanceResourceId]
        : [];
    })
  );
  const fonts = result.resources
    .filter((resource) => resource.kind === 'fontResource' && usedFonts.has(resource.id))
    .map(({ id, mediaType, bytes }) => ({
      id,
      mediaType,
      base64: Buffer.from(bytes).toString('base64')
    }));
  if (fonts.length !== usedFonts.size) {
    error(502, 'Compiled example is missing a required font resource.');
  }

  return json(
    {
      exampleId: input.exampleId,
      seed,
      source: template.source,
      visualization: result.visualization,
      fonts
    },
    { headers: { 'cache-control': 'private, no-store' } }
  );
};
