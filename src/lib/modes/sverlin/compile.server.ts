/** Compile one untrusted Svelte component without executing its code on the server. */

import { posix } from 'node:path';

import { build, type BuildFailure, type Plugin } from 'esbuild';
import { compile, parse } from 'svelte/compiler';

import entrySource from './assembly/entry.ts?raw';
import preludeSource from './assembly/prelude.ts?raw';
import {
  AlgorithmError,
  declaredNames,
  interpretAlgorithm,
  interpretDesign,
  interpretDomain,
  interpretInput,
  type BlockKind,
  type MasterStep,
  type TraceState
} from './algorithm/interpret.server';
import { noAtoms, type AtomRegistry } from './algorithm/atoms.server';

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

/** Component names the prelude brings into scope, which values must not shadow. */
const libraryNames = [...prelude.matchAll(/import\s*\{([^}]*)\}/gu)].flatMap(([, names]) =>
  names
    .split(',')
    .map((name) => name.trim())
    .filter(Boolean)
);

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
  atoms: AtomRegistry;
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
    const authoredScript = ast.instance ?? ast.module;
    if (authoredScript)
      throw new InvalidSvelteSourceError(
        'Views cannot have their own <script>: input, algorithm, and design values, step, seed, and the library components are already in scope. Compute in markup, using {@const} inside a block or component for reuse.',
        { code: 'view_script', start: sourcePosition(source, authoredScript.start) }
      );
    if (!blocks.algorithm)
      throw new InvalidSvelteSourceError(
        'Add a <script lang="sverlin"> algorithm block whose yield statements mark the steps, such as yield "Start";'
      );
    const atoms = blocks.domain
      ? interpretBlock(source, blocks.domain, (body) => interpretDomain(body))
      : noAtoms;
    const shadowed = Object.keys(atoms).find((name) => libraryNames.includes(name));
    if (shadowed)
      throw new InvalidSvelteSourceError(
        `"${shadowed}" names a library component; choose another type name.`
      );
    const input = blocks.input
      ? interpretBlock(source, blocks.input, (body) => interpretInput(body, atoms))
      : { state: {}, types: {} };
    const master = interpretBlock(source, blocks.algorithm, (body) =>
      interpretAlgorithm(body, input, atoms)
    );
    const stateNames = Object.keys(master[0].state);
    const designNames = blocks.design
      ? interpretBlock(source, blocks.design, (body) => declaredNames(body, 'design'))
      : [];
    const clash = designNames.find((name) => stateNames.includes(name));
    if (clash)
      throw new InvalidSvelteSourceError(
        `"${clash}" is defined in the design block and in the input or algorithm block.`
      );
    const props = [...stateNames, ...designNames];
    const typeName = props.find((name) => Object.hasOwn(atoms, name));
    if (typeName)
      throw new InvalidSvelteSourceError(
        `"${typeName}" names an atomic type; choose another variable name.`
      );
    const library = props.find((name) => libraryNames.includes(name));
    if (library)
      throw new InvalidSvelteSourceError(
        `"${library}" names a library component; choose another variable name.`
      );
    const renderers = typeRenderers(ast, atoms, source);
    const component = compile(withGeneratedScripts(svelteSource, props, renderers), {
      filename: 'Main.svelte',
      generate: 'client',
      css: 'injected',
      dev: false
    }).js.code;
    return {
      source,
      component,
      master,
      atoms,
      ...(blocks.design ? { design: blocks.design } : {})
    };
  } catch (cause) {
    if (cause instanceof InvalidSvelteSourceError) throw cause;
    throw new InvalidSvelteSourceError(
      cause instanceof Error ? cause.message : String(cause),
      cause
    );
  }
}

/** Draw one seed's design and bundle the presentation with every step's state. */
export async function bundlePresentation(
  prepared: PreparedComponent,
  seed: number
): Promise<SvelteBundle> {
  const { master } = prepared;
  const parameters = prepared.design
    ? interpretBlock(prepared.source, prepared.design, (body) => interpretDesign(body, seed))
    : {};
  // Every presentation shows every master step until steps can be mapped to frames.
  const masterSteps = master.map((_, index) => index);
  // Each step's state carries its atomic types for the view, under a key no variable can use.
  const states = masterSteps.map((index) => ({
    ...master[index].state,
    ...parameters,
    __types: master[index].types
  }));
  const result = await bundle(
    prepared.component,
    JSON.stringify(states),
    JSON.stringify(prepared.atoms)
  );
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
  /<script\s+lang\s*=\s*(["'])sverlin\1(?:\s+(domain|input|design))?\s*>([\s\S]*?)<\/script\s*>/giu;

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
  const unrecognized = /<script\b[^>]*\blang\s*=\s*(["'])sverlin\1[^>]*>/iu.exec(svelteSource);
  if (unrecognized)
    throw new InvalidSvelteSourceError(
      `Unrecognized sverlin block ${unrecognized[0]}; use <script lang="sverlin">, or add domain, input, or design, as in <script lang="sverlin" input>.`,
      { code: 'sverlin_block', start: sourcePosition(source, unrecognized.index) }
    );
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

/**
 * Give the script-free view its scripts: the library prelude and every recorded or design value,
 * plus step and seed, as props. Both share the first line so authored line numbers are unchanged.
 */
function withGeneratedScripts(
  source: string,
  props: readonly string[],
  renderers: readonly string[]
): string {
  const names = [...props, 'step', 'seed'].join(', ');
  // Type renderers are the view's own top-level snippets, which its script may refer to.
  const registration = renderers.length
    ? `import { setContext as __sverlinSetContext } from 'svelte'; __sverlinSetContext('sverlin:renderers', { ${renderers.join(', ')} });`
    : '';
  return `<script module>${prelude}</script><script>let { ${names} } = $props(); ${registration}</script>${source}`;
}

/**
 * Top-level snippets named after a domain type render every value of that type, taking the value
 * and the props its node was given, as in {#snippet Int(value, node)} … {/snippet}.
 */
function typeRenderers(
  ast: { html?: { children?: unknown[] } },
  atoms: AtomRegistry,
  source: string
): string[] {
  return (ast.html?.children ?? []).flatMap((node) => {
    const snippet = node as {
      type: string;
      start: number;
      expression?: { name?: string };
      parameters?: unknown[];
    };
    const name = snippet.expression?.name;
    if (snippet.type !== 'SnippetBlock' || !name || !Object.hasOwn(atoms, name)) return [];
    if ((snippet.parameters?.length ?? 0) > 2)
      throw new InvalidSvelteSourceError(
        `The ${name} renderer takes at most (value, node), as in {#snippet ${name}(value, node)}.`,
        { code: 'type_renderer', start: sourcePosition(source, snippet.start) }
      );
    return [name];
  });
}

async function bundle(component: string, states: string, atoms: string) {
  try {
    return await bundleComponent(component, states, atoms);
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
  entry: (path) =>
    runtime(path) ||
    ['virtual:component', 'virtual:trace', 'virtual:atoms', 'sverlin'].includes(path),
  component: (path) => runtime(path) || path === 'sverlin',
  library: (path) => runtime(path) || /^\.\.?\//u.test(path)
};

function sandboxModules(component: string, states: string, atoms: string): Plugin {
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
        if (args.path === 'virtual:atoms') return { path: 'atoms.json', namespace: 'atoms' };
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
      plugin.onLoad({ filter: /.*/, namespace: 'atoms' }, () => ({
        contents: atoms,
        loader: 'json'
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

function bundleComponent(component: string, states: string, atoms: string) {
  return build({
    entryPoints: ['virtual:entry'],
    plugins: [sandboxModules(component, states, atoms)],
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
