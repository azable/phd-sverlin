/** Compile one untrusted Svelte component without executing its code on the server. */

import { build } from 'esbuild';
import { compile, parse } from 'svelte/compiler';

// One component should be much smaller; these ceilings bound compilation and inline Timeline storage.
const maximumSourceBytes = 256 * 1024;
const maximumBundleBytes = 2 * 1024 * 1024;

export type SvelteBundle = { javascript: string; labels: string[] };

export class InvalidSvelteSourceError extends Error {
  readonly code?: string;
  readonly line?: number;
  readonly column?: number;

  constructor(message: string, cause?: unknown) {
    super(message);
    this.name = 'InvalidSvelteSourceError';
    const issue = cause as
      | { code?: unknown; start?: { line?: unknown; column?: unknown } }
      | undefined;
    if (typeof issue?.code === 'string') this.code = issue.code;
    if (typeof issue?.start?.line === 'number' && issue.start.line >= 1)
      this.line = issue.start.line;
    if (typeof issue?.start?.column === 'number' && issue.start.column >= 0)
      this.column = issue.start.column + 1;
  }
}

/** Only a single, self-contained component is accepted; its runtime is bundled locally. */
export async function compileSvelteComponent(source: string): Promise<SvelteBundle> {
  if (Buffer.byteLength(source, 'utf8') > maximumSourceBytes) {
    throw new InvalidSvelteSourceError('The Svelte component is too large.');
  }
  let labels: string[];
  let component: string;
  try {
    const ast = parse(source, { filename: 'Main.svelte' });
    visit(ast, (node) => {
      if (
        node.type === 'ImportDeclaration' ||
        node.type === 'ImportExpression' ||
        node.type === 'ExportAllDeclaration' ||
        (node.type === 'ExportNamedDeclaration' && 'source' in node && node.source)
      )
        throw new InvalidSvelteSourceError('Generated components cannot import other modules.');
    });
    labels = componentLabels(ast.module?.content.body ?? []);
    component = compile(source, {
      filename: 'Main.svelte',
      generate: 'client',
      css: 'injected',
      dev: false
    }).js.code;
  } catch (cause) {
    if (cause instanceof InvalidSvelteSourceError) throw cause;
    throw new InvalidSvelteSourceError(
      cause instanceof Error ? cause.message : String(cause),
      cause
    );
  }
  const result = await build({
    stdin: {
      contents: `import { mount } from 'svelte';\nimport Main from 'virtual:component';\nmount(Main, { target: document.getElementById('app'), props: { step: window.__sverlinStep, seed: window.__sverlinSeed } });`,
      resolveDir: process.cwd(),
      sourcefile: 'entry.js'
    },
    plugins: [
      {
        name: 'component-source',
        setup(plugin) {
          plugin.onResolve({ filter: /^virtual:component$/ }, () => ({
            path: 'component',
            namespace: 'generated'
          }));
          plugin.onLoad({ filter: /.*/, namespace: 'generated' }, () => ({
            contents: component,
            loader: 'js',
            resolveDir: process.cwd()
          }));
        }
      }
    ],
    bundle: true,
    write: false,
    platform: 'browser',
    format: 'iife',
    target: 'es2022',
    minify: true,
    logLevel: 'silent'
  });
  const output = result.outputFiles[0];
  if (output.contents.byteLength > maximumBundleBytes) {
    throw new InvalidSvelteSourceError('The compiled Svelte presentation is too large.');
  }
  return { javascript: output.text, labels };
}

function visit(value: unknown, check: (node: { type: string }) => void): void {
  if (!value || typeof value !== 'object') return;
  if (Array.isArray(value)) {
    value.forEach((part) => visit(part, check));
    return;
  }
  const node = value as Record<string, unknown>;
  if (typeof node.type === 'string') check(node as { type: string });
  for (const [key, child] of Object.entries(node)) {
    if (key !== 'parent' && key !== 'metadata') visit(child, check);
  }
}

function componentLabels(body: readonly { type: string }[]): string[] {
  for (const statement of body) {
    if (statement.type !== 'ExportNamedDeclaration') continue;
    const declaration = (
      statement as {
        declaration?: {
          declarations?: Array<{
            id: { name?: string };
            init?: { type: string; elements?: Array<{ type: string; value?: unknown }> };
          }>;
        };
      }
    ).declaration;
    for (const item of declaration?.declarations ?? []) {
      if (item.id.name !== 'steps') continue;
      const elements = item.init?.type === 'ArrayExpression' ? item.init.elements : undefined;
      if (
        !elements ||
        elements.length === 0 ||
        elements.length > 100 ||
        elements.some(
          (element) =>
            element.type !== 'Literal' || typeof element.value !== 'string' || !element.value.trim()
        )
      ) {
        throw new Error('Exported steps must be a nonempty array of up to 100 string labels.');
      }
      const labels = elements.map((element) => element.value as string);
      if (new Set(labels).size !== labels.length) {
        throw new Error('Exported step labels must be unique.');
      }
      return labels;
    }
  }
  return ['Start'];
}
