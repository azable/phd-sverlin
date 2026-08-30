/** Validation and isolation helpers for AI- or user-authored static HTML frames. */

import sanitizeHtml from 'sanitize-html';
import * as v from 'valibot';

import {
  htmlFramesManifestSchema,
  staticHtmlFrameDocument,
  type HtmlFramesManifest
} from '$lib/shared/presentations';

const maximumManifestBytes = 512 * 1024;
const forbiddenMarkup =
  /<(?:script|iframe|frame|object|embed|form|input|button|textarea|select|base|meta|link)\b|\son[a-z]+\s*=|javascript\s*:|data\s*:\s*text\/html|@import\b/iu;
const remoteCssUrl = /url\s*\(\s*(['"]?)(?!data:image\/)[^)]+\1\s*\)/iu;
const remoteMarkupUrl = /\s(?:src|href)\s*=\s*(['"])(?!data:|#)[^'"]+\1/iu;

const allowedTags = [
  ...sanitizeHtml.defaults.allowedTags,
  'article',
  'aside',
  'figure',
  'figcaption',
  'main',
  'section',
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
];

/** Parse, size-check, and sanitize a complete editable HTML-frame manifest. */
export function validateHtmlFramesManifest(value: unknown): {
  authored: HtmlFramesManifest;
  rendered: HtmlFramesManifest;
} {
  const parsed = v.safeParse(htmlFramesManifestSchema, value);
  if (!parsed.success)
    throw new Error(`Invalid HTML frame manifest: ${v.summarize(parsed.issues)}`);
  const serialized = JSON.stringify(parsed.output);
  if (Buffer.byteLength(serialized, 'utf8') > maximumManifestBytes) {
    throw new Error(`HTML frame manifest exceeds the ${maximumManifestBytes} byte limit.`);
  }
  const labels = parsed.output.frames.map(({ label }) => label);
  if (new Set(labels).size !== labels.length) throw new Error('HTML frame labels must be unique.');

  return {
    authored: parsed.output,
    rendered: {
      ...parsed.output,
      frames: parsed.output.frames.map((frame) => ({
        ...frame,
        html: sanitizeFrame(frame.html)
      }))
    }
  };
}

/** Wrap one safe fragment in an opaque, no-network iframe document. */
export function htmlFrameSourceDocument(html: string): string {
  return staticHtmlFrameDocument(html);
}

function sanitizeFrame(html: string): string {
  if (forbiddenMarkup.test(html) || remoteCssUrl.test(html) || remoteMarkupUrl.test(html)) {
    throw new Error(
      'HTML frames must be static and cannot contain scripts, controls, frames, or remote resources.'
    );
  }
  const rendered = sanitizeHtml(html, {
    allowedTags,
    // Inline CSS is an explicit format capability; sanitizer validation and the opaque
    // iframe's no-network/no-script CSP provide the surrounding safety boundary.
    allowVulnerableTags: true,
    allowedAttributes: {
      '*': ['id', 'class', 'style', 'title', 'role', 'aria-*', 'data-*'],
      img: ['src', 'alt', 'width', 'height'],
      svg: ['viewBox', 'width', 'height', 'fill', 'stroke', 'aria-*'],
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
    allowedSchemes: ['data'],
    allowProtocolRelative: false,
    disallowedTagsMode: 'discard'
  });
  if (!rendered.trim()) throw new Error('HTML frames cannot be empty after validation.');
  return rendered;
}
