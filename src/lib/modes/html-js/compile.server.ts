/** Package separately authored HTML and JavaScript after sanitizing the HTML. */

import sanitizeHtml from 'sanitize-html';
import * as v from 'valibot';
import { transform } from 'esbuild';
import { parse } from 'acorn';

export const htmlJsSourceSchema = v.strictObject({
  format: v.literal('html-js-v1'),
  html: v.string(),
  javascript: v.string()
});

export type HtmlJsSource = v.InferOutput<typeof htmlJsSourceSchema>;

export async function compileHtmlJs(value: unknown): Promise<{ html: string; javascript: string }> {
  const source = v.parse(htmlJsSourceSchema, value);
  // A generous single-artifact ceiling bounds parser work and recorded source size.
  if (Buffer.byteLength(JSON.stringify(source), 'utf8') > 256 * 1024) {
    throw new Error('The HTML/JS source is too large.');
  }
  const html = sanitizeHtml(source.html, {
    allowedTags: [
      ...sanitizeHtml.defaults.allowedTags,
      'style',
      'svg',
      'path',
      'circle',
      'rect',
      'g'
    ],
    allowedAttributes: {
      '*': ['id', 'class', 'style', 'role', 'aria-*'],
      svg: ['viewBox'],
      path: ['d', 'fill'],
      circle: ['cx', 'cy', 'r', 'fill'],
      rect: ['x', 'y', 'width', 'height', 'fill']
    },
    allowVulnerableTags: true,
    allowedSchemes: [],
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
  return { html, javascript: output.code };
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
