/** Compile one untrusted Svelte component without executing its code on the server. */

import { posix } from 'node:path';

import { build, type BuildFailure, type Plugin } from 'esbuild';
import { compile, parse } from 'svelte/compiler';

import entrySource from './assembly/entry.ts?raw';
import preludeSource from './assembly/prelude.ts?raw';
import { AlgorithmError, interpretAlgorithm, type TraceStep } from './algorithm/interpret.server';

// One component should be much smaller; these ceilings bound compilation and inline Timeline storage.
const maximumSourceBytes = 256 * 1024;
const maximumBundleBytes = 2 * 1024 * 1024;

// Library sources are embedded at build time so production needs no source tree.
const librarySources = Object.fromEntries(
  Object.entries(
    import.meta.glob<string>('./library/**/*.{svelte,ts}', {
      query: '?raw',
      import: 'default',
      eager: true
    })
  ).map(([path, text]) => [path.slice('./library/'.length), text])
);
const compiledLibrary = new Map<string, string>();

/** The prelude's import statements on one line, so injection keeps authored line numbers. */
const prelude = (preludeSource.match(/^import[\s\S]*?;/gmu) ?? [])
  .map((statement) => statement.replace(/\s+/gu, ' '))
  .join(' ');

function libraryPath(path: string): string | undefined {
  return [path, `${path}.ts`, `${path}/index.ts`].find((candidate) => candidate in librarySources);
}

function loadLibraryModule(path: string): { contents: string; loader: 'js' | 'ts' } {
  const source = librarySources[path];
  if (!path.endsWith('.svelte')) return { contents: source, loader: 'ts' };
  let contents = compiledLibrary.get(path);
  if (contents === undefined) {
    contents = compile(source, {
      filename: path,
      generate: 'client',
      css: 'injected',
      dev: false
    }).js.code;
    compiledLibrary.set(path, contents);
  }
  return { contents, loader: 'js' };
}

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

/** Only a single component is accepted; its runtime and the component library are bundled locally. */
export async function compileSvelteComponent(source: string): Promise<SvelteBundle> {
  if (Buffer.byteLength(source, 'utf8') > maximumSourceBytes) {
    throw new InvalidSvelteSourceError('The Svelte component is too large.');
  }
  let labels: string[];
  let states: TraceStep['state'][];
  let component: string;
  try {
    const { svelteSource, algorithm } = extractAlgorithm(source);
    const ast = parse(svelteSource, { filename: 'Main.svelte' });
    visit(ast, (node) => {
      if (
        node.type === 'ImportDeclaration' ||
        node.type === 'ImportExpression' ||
        node.type === 'ExportAllDeclaration' ||
        (node.type === 'ExportNamedDeclaration' && 'source' in node && node.source)
      )
        throw new InvalidSvelteSourceError(
          'Generated components cannot import modules; library components are already in scope.'
        );
    });
    const exportedSteps = componentLabels(ast.module?.content.body ?? []);
    if (algorithm) {
      if (exportedSteps)
        throw new InvalidSvelteSourceError(
          'Use yield in the algorithm block or export const steps, not both.'
        );
      const trace = traceAlgorithm(source, algorithm);
      labels = trace.map(({ label }) => label);
      states = trace.map(({ state }) => state);
    } else {
      labels = exportedSteps ?? ['Start'];
      states = labels.map(() => ({}));
    }
    component = compile(withPrelude(svelteSource, ast.module?.start), {
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
  const result = await bundle(component, JSON.stringify(states));
  const output = result.outputFiles[0];
  if (output.contents.byteLength > maximumBundleBytes) {
    throw new InvalidSvelteSourceError('The compiled Svelte presentation is too large.');
  }
  return { javascript: output.text, labels };
}

const algorithmBlock = /<script\s+lang\s*=\s*(["'])sverlin\1\s*>([\s\S]*?)<\/script\s*>/giu;

/** Remove the algorithm block for Svelte, keeping every offset and line in place. */
function extractAlgorithm(source: string): {
  svelteSource: string;
  algorithm?: { body: string; offset: number };
} {
  const blocks = [...source.matchAll(algorithmBlock)];
  if (blocks.length === 0) return { svelteSource: source };
  if (blocks.length > 1)
    throw new InvalidSvelteSourceError('A component can have only one algorithm block.');
  const [block] = blocks;
  const start = block.index;
  return {
    svelteSource:
      source.slice(0, start) +
      block[0].replace(/[^\n]/gu, ' ') +
      source.slice(start + block[0].length),
    algorithm: { body: block[2], offset: start + block[0].indexOf('>') + 1 }
  };
}

/** Interpret the algorithm, reporting failures at their position in the authored source. */
function traceAlgorithm(source: string, algorithm: { body: string; offset: number }): TraceStep[] {
  try {
    return interpretAlgorithm(algorithm.body);
  } catch (cause) {
    if (!(cause instanceof AlgorithmError)) throw cause;
    const position =
      cause.offset === undefined
        ? undefined
        : sourcePosition(source, algorithm.offset + cause.offset);
    throw new InvalidSvelteSourceError(cause.message, { code: 'algorithm_error', start: position });
  }
}

function sourcePosition(source: string, offset: number): { line: number; column: number } {
  const before = source.slice(0, offset);
  const lineStart = before.lastIndexOf('\n') + 1;
  return { line: before.split('\n').length, column: offset - lineStart };
}

/** Insert the prelude right after the module script's opening tag, or add a module script. */
function withPrelude(source: string, moduleStart: number | undefined): string {
  if (moduleStart === undefined) return `<script module>${prelude}</script>${source}`;
  const contentStart = source.indexOf('>', moduleStart) + 1;
  return `${source.slice(0, contentStart)}${prelude}${source.slice(contentStart)}`;
}

async function bundle(component: string, states: string) {
  try {
    return await bundleComponent(component, states);
  } catch (cause) {
    // Failures located in the authored component, such as a blocked require(), are source errors.
    const authored = (cause as Partial<BuildFailure>).errors?.find(
      (error) => error.location?.file === 'component:Main.svelte'
    );
    if (authored) throw new InvalidSvelteSourceError(authored.text);
    throw cause;
  }
}

// Svelte runtime entry points only; no relative segments that could leave the package.
const runtime = (path: string) => /^svelte(?:\/[\w-]+)*$/u.test(path);

/** Modules each sandbox namespace may reach; packages inside node_modules resolve normally. */
const allowedImports: Record<string, (path: string) => boolean> = {
  entry: (path) => runtime(path) || path === 'virtual:component' || path === 'virtual:trace',
  component: (path) => runtime(path) || path === 'sverlin',
  library: (path) => runtime(path) || /^\.\.?\//u.test(path)
};

function sandboxModules(component: string, states: string): Plugin {
  return {
    name: 'sandbox-modules',
    setup(plugin) {
      plugin.onResolve({ filter: /.*/ }, (args) => {
        const allowed = allowedImports[args.namespace];
        if (!allowed) return undefined;
        if (!allowed(args.path))
          return { errors: [{ text: `Presentations cannot load module "${args.path}".` }] };
        if (args.path === 'virtual:component')
          return { path: 'Main.svelte', namespace: 'component' };
        if (args.path === 'virtual:trace') return { path: 'states.json', namespace: 'trace' };
        if (args.path === 'sverlin') return { path: 'index.ts', namespace: 'library' };
        if (args.namespace === 'library' && !runtime(args.path)) {
          const path = libraryPath(posix.join(posix.dirname(args.importer), args.path));
          return path
            ? { path, namespace: 'library' }
            : { errors: [{ text: `Unknown library module ${args.path}.` }] };
        }
        return undefined;
      });
      plugin.onResolve({ filter: /^virtual:entry$/ }, () => ({
        path: 'entry.ts',
        namespace: 'entry'
      }));
      plugin.onLoad({ filter: /.*/, namespace: 'entry' }, () => ({
        contents: entrySource,
        loader: 'ts',
        resolveDir: process.cwd()
      }));
      plugin.onLoad({ filter: /.*/, namespace: 'component' }, () => ({
        contents: component,
        loader: 'js',
        resolveDir: process.cwd()
      }));
      plugin.onLoad({ filter: /.*/, namespace: 'trace' }, () => ({
        contents: states,
        loader: 'json'
      }));
      plugin.onLoad({ filter: /.*/, namespace: 'library' }, (args) => ({
        ...loadLibraryModule(args.path),
        resolveDir: process.cwd()
      }));
    }
  };
}

function bundleComponent(component: string, states: string) {
  return build({
    entryPoints: ['virtual:entry'],
    plugins: [sandboxModules(component, states)],
    bundle: true,
    write: false,
    platform: 'browser',
    format: 'iife',
    target: 'es2022',
    minify: true,
    logLevel: 'silent'
  });
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

function componentLabels(body: readonly { type: string }[]): string[] | undefined {
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
  return undefined;
}
