/** Compile one untrusted Svelte component without executing its code on the server. */

import { posix } from 'node:path';

import { build, type BuildFailure, type Plugin } from 'esbuild';
import { compile, parse } from 'svelte/compiler';

import entrySource from './assembly/entry.ts?raw';
import preludeSource from './assembly/prelude.ts?raw';
import {
  AlgorithmError,
  interpretAlgorithm,
  interpretDesign,
  interpretInput,
  selectSteps,
  type BlockKind,
  type MasterStep,
  type TraceState
} from './algorithm/interpret.server';

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

/** One seeded presentation of a prepared component. */
export type SvelteBundle = {
  javascript: string;
  /** Labels of the steps this presentation keeps. */
  labels: string[];
  /** Labels of every master step, shared by all presentations of the source. */
  masterLabels: string[];
  /** Master step index of each kept step. */
  masterSteps: number[];
  /** Design values drawn for this presentation. */
  parameters: TraceState;
};

type Block = { body: string; offset: number };

/** Seed-independent result of checking, interpreting, and compiling one component. */
export type PreparedComponent = {
  source: string;
  component: string;
  master: MasterStep[];
  design?: Block;
};

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

/** Compile one seeded presentation; batch builds prepare once and bundle per seed instead. */
export async function compileSvelteComponent(source: string, seed = 1): Promise<SvelteBundle> {
  return bundlePresentation(prepareSvelteComponent(source), seed);
}

/**
 * Check, interpret, and compile once per source. Only a single component is accepted; its
 * runtime and the component library are bundled locally, and only the design depends on the seed.
 */
export function prepareSvelteComponent(source: string): PreparedComponent {
  if (Buffer.byteLength(source, 'utf8') > maximumSourceBytes) {
    throw new InvalidSvelteSourceError('The Svelte component is too large.');
  }
  try {
    const { svelteSource, blocks } = extractBlocks(source);
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
    if (!blocks.algorithm)
      throw new InvalidSvelteSourceError(
        'Add a <script lang="sverlin"> algorithm block whose yield statements mark the steps, such as yield "Start";'
      );
    const input = blocks.input
      ? interpretBlock(source, blocks.input, (body) => interpretInput(body))
      : {};
    const master = interpretBlock(source, blocks.algorithm, (body) =>
      interpretAlgorithm(body, input)
    );
    const component = compile(withPrelude(svelteSource, ast.module?.start), {
      filename: 'Main.svelte',
      generate: 'client',
      css: 'injected',
      dev: false
    }).js.code;
    return { source, component, master, ...(blocks.design ? { design: blocks.design } : {}) };
  } catch (cause) {
    if (cause instanceof InvalidSvelteSourceError) throw cause;
    throw new InvalidSvelteSourceError(
      cause instanceof Error ? cause.message : String(cause),
      cause
    );
  }
}

/** Draw one seed's design, keep its steps, and bundle the presentation with those states. */
export async function bundlePresentation(
  prepared: PreparedComponent,
  seed: number
): Promise<SvelteBundle> {
  const { master } = prepared;
  const parameters = prepared.design
    ? interpretBlock(prepared.source, prepared.design, (body) => interpretDesign(body, seed))
    : {};
  const clash = Object.keys(master[0]?.state ?? {}).find((name) => name in parameters);
  if (clash)
    throw new InvalidSvelteSourceError(
      `"${clash}" is defined in the design block and in the input or algorithm block.`
    );
  const masterSteps = selectSteps(master, parameters, seed);
  const states = masterSteps.map((index) => ({ ...master[index].state, ...parameters }));
  const result = await bundle(prepared.component, JSON.stringify(states));
  const output = result.outputFiles[0];
  if (output.contents.byteLength > maximumBundleBytes) {
    throw new InvalidSvelteSourceError('The compiled Svelte presentation is too large.');
  }
  return {
    javascript: output.text,
    labels: masterSteps.map((index) => master[index].label),
    masterLabels: master.map(({ label }) => label),
    masterSteps,
    parameters
  };
}

const sverlinBlock =
  /<script\s+lang\s*=\s*(["'])sverlin\1(?:\s+(input|design))?\s*>([\s\S]*?)<\/script\s*>/giu;

/** Remove the Sverlin blocks for Svelte, keeping every offset and line in place. */
function extractBlocks(source: string): {
  svelteSource: string;
  blocks: Partial<Record<BlockKind, Block>>;
} {
  const blocks: Partial<Record<BlockKind, Block>> = {};
  let svelteSource = source;
  for (const match of source.matchAll(sverlinBlock)) {
    const kind = (match[2] ?? 'algorithm') as BlockKind;
    if (blocks[kind])
      throw new InvalidSvelteSourceError(`A component can have only one ${kind} block.`);
    const start = match.index;
    blocks[kind] = { body: match[3], offset: start + match[0].indexOf('>') + 1 };
    svelteSource =
      svelteSource.slice(0, start) +
      match[0].replace(/[^\n]/gu, ' ') +
      svelteSource.slice(start + match[0].length);
  }
  return { svelteSource, blocks };
}

/** Interpret one block, reporting failures at their position in the authored source. */
function interpretBlock<T>(source: string, block: Block, run: (body: string) => T): T {
  try {
    return run(block.body);
  } catch (cause) {
    if (!(cause instanceof AlgorithmError)) throw cause;
    const position =
      cause.offset === undefined ? undefined : sourcePosition(source, block.offset + cause.offset);
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
