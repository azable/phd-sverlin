/** Package separately authored HTML and JavaScript after sanitizing the HTML. */

import sanitizeHtml from 'sanitize-html';
import * as v from 'valibot';
import { transform } from 'esbuild';
import { parse } from 'acorn';

export const htmlJsSourceSchema = v.strictObject({
  format: v.literal('html-js-v1'),
  /**
   * One label per step of the algorithm, in order. The page loads once per step, with the step's
   * index as window.__sverlinStep; a source without steps has the single step "Start".
   */
  steps: v.optional(
    v.pipe(
      v.array(v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(120))),
      v.minLength(1),
      v.maxLength(200)
    )
  ),
  html: v.string(),
  javascript: v.string()
});

export type HtmlJsSource = v.InferOutput<typeof htmlJsSourceSchema>;

export async function compileHtmlJs(
  value: unknown
): Promise<{ html: string; javascript: string; steps: string[] }> {
  const parsed = v.safeParse(htmlJsSourceSchema, value);
  if (!parsed.success)
    throw new Error(`The HTML/JS source is not valid: ${v.summarize(parsed.issues)}`);
  const source = parsed.output;
  // A generous single-artifact ceiling bounds parser work and recorded source size.
  if (Buffer.byteLength(JSON.stringify(source), 'utf8') > 256 * 1024) {
    throw new Error('The HTML/JS source is too large.');
  }
  const html = sanitizeHtml(source.html, {
    // The same static SVG as HTML frames allow, so markup is not silently stripped.
    allowedTags: [
      ...sanitizeHtml.defaults.allowedTags,
      'style',
      'svg',
      'g',
      'defs',
      'path',
      'circle',
      'ellipse',
      'rect',
      'line',
      'polyline',
      'polygon',
      'text',
      'tspan',
      'linearGradient',
      'radialGradient',
      'stop'
    ],
    allowedAttributes: {
      '*': ['id', 'class', 'style', 'title', 'role', 'aria-*', 'data-*'],
      svg: ['viewBox', 'width', 'height', 'preserveAspectRatio', 'fill', 'stroke'],
      g: ['transform', 'fill', 'stroke', 'opacity'],
      path: ['d', 'fill', 'stroke', 'stroke-width', 'opacity', 'transform'],
      circle: ['cx', 'cy', 'r', 'fill', 'stroke', 'stroke-width', 'opacity'],
      ellipse: ['cx', 'cy', 'rx', 'ry', 'fill', 'stroke', 'stroke-width', 'opacity'],
      rect: ['x', 'y', 'width', 'height', 'rx', 'ry', 'fill', 'stroke', 'stroke-width', 'opacity'],
      line: ['x1', 'y1', 'x2', 'y2', 'stroke', 'stroke-width', 'opacity'],
      polyline: ['points', 'fill', 'stroke', 'stroke-width', 'opacity'],
      polygon: ['points', 'fill', 'stroke', 'stroke-width', 'opacity'],
      text: ['x', 'y', 'dx', 'dy', 'fill', 'font-size', 'text-anchor', 'transform'],
      tspan: ['x', 'y', 'dx', 'dy', 'fill'],
      linearGradient: ['id', 'x1', 'y1', 'x2', 'y2'],
      radialGradient: ['id', 'cx', 'cy', 'r'],
      stop: ['offset', 'stop-color', 'stop-opacity']
    },
    allowVulnerableTags: true,
    allowedSchemes: [],
    // SVG attributes are case-sensitive, such as viewBox; lowercased, they would not match and be dropped.
    parser: { lowerCaseAttributeNames: false },
    disallowedTagsMode: 'discard'
  });
  if (!html.trim()) throw new Error('The HTML/JS source has no safe markup.');
  const ast = parse(source.javascript, { ecmaVersion: 'latest', sourceType: 'module' });
  visit(ast, (type) => {
    if (type === 'ImportDeclaration' || type === 'ImportExpression' || type.startsWith('Export')) {
      throw new Error('Generated HTML/JS cannot import or export modules.');
    }
  });
  const output = await transform(source.javascript, {
    loader: 'js',
    target: 'es2022',
    format: 'iife',
    logLevel: 'silent'
  });
  return { html, javascript: output.code, steps: numbered(source.steps ?? ['Start']) };
}

/** Step labels identify steps, so a repeated one is numbered by its occurrence, as in "Visit (2)". */
function numbered(labels: readonly string[]): string[] {
  const seen = new Set<string>();
  return labels.map((label) => {
    let unique = label;
    for (let occurrence = 2; seen.has(unique); occurrence++) unique = `${label} (${occurrence})`;
    seen.add(unique);
    return unique;
  });
}

function visit(value: unknown, check: (type: string) => void): void {
  if (!value || typeof value !== 'object') return;
  if (Array.isArray(value)) {
    value.forEach((part) => visit(part, check));
    return;
  }
  const node = value as Record<string, unknown>;
  if (typeof node.type === 'string') check(node.type);
  for (const child of Object.values(node)) visit(child, check);
}
