import { describe, expect, it } from 'vitest';

import {
  bundlePresentation,
  compileSvelteComponent,
  InvalidSvelteSourceError,
  prepareSvelteComponent
} from './compile.server';
import { linearSearchSource } from './contract';
import libraryGuide from './library/README.md?raw';

describe('single-component Svelte compilation', () => {
  it('bundles a component and its playback input without executing it', async () => {
    const result = await compileSvelteComponent(
      '<script lang="sverlin">yield "First"; yield "Second";</script><h1>{step}</h1>'
    );
    expect(result.labels).toEqual(['First', 'Second']);
    expect(result.javascript).toContain('__sverlinStep');
    expect(result.javascript).not.toContain('import "svelte');
  });

  it('rejects imports in instance and module code', async () => {
    await expect(
      compileSvelteComponent(
        '<script>import x from "https://example.com/x.js";</script><h1>{x}</h1>'
      )
    ).rejects.toThrow('cannot import');
    await expect(
      compileSvelteComponent('<script module>import x from "other";</script><h1>{x}</h1>')
    ).rejects.toThrow('cannot import');
    await expect(
      compileSvelteComponent('<script>const x = import("/secret")</script><h1>{x}</h1>')
    ).rejects.toThrow('cannot import');
    await expect(compileSvelteComponent('<h1>{import(window.target)}</h1>')).rejects.toThrow(
      'cannot import'
    );
  });

  it('derives master steps from yield and varies only the design between seeds', async () => {
    const master = [
      'Start',
      'Compare index 0',
      'Compare index 1',
      'Compare index 2',
      'Found 2 at index 3'
    ];
    const prepared = prepareSvelteComponent(linearSearchSource);
    expect(prepared.master.map(({ label }) => label)).toEqual(master);
    const bundles = await Promise.all(
      Array.from({ length: 12 }, (_, seed) => bundlePresentation(prepared, seed + 1))
    );
    for (const bundle of bundles) {
      expect(bundle.masterLabels).toEqual(master);
      expect(bundle.labels).toEqual(master);
      expect(bundle.masterSteps).toEqual([0, 1, 2, 3, 4]);
      expect(['i', 'index', '↑']).toContain(bundle.parameters.pointerName);
    }
    expect(new Set(bundles.map(({ parameters }) => parameters.showIndices))).toEqual(
      new Set([true, false])
    );
    expect(bundles[0].javascript).toContain('[3,8,5,2,7]');
    expect(bundles[0].javascript).not.toContain('yield `Compare');
    const again = await bundlePresentation(prepared, 1);
    expect(again.parameters).toEqual(bundles[0].parameters);
  });

  it('builds the example in the library guide sent to the assistant', async () => {
    const example = libraryGuide.match(/```svelte\n([\s\S]*?)```/u)?.[1];
    expect(example).toBeDefined();
    const result = await compileSvelteComponent(example ?? '');
    expect(result.masterLabels).toEqual([
      'Start',
      'Visit index 0',
      'Visit index 1',
      'Visit index 2',
      'Done'
    ]);
  });

  it('reports design errors at their authored position and rejects name clashes', async () => {
    const design =
      '<script lang="sverlin">\nlet x = 1;\nyield "A";\n</script>\n<script lang="sverlin" design>\nconst size = int(4, 1);\n</script>';
    await expect(compileSvelteComponent(design)).rejects.toMatchObject({
      code: 'algorithm_error',
      line: 6,
      message: expect.stringContaining('minimum ≤ maximum')
    });
    await expect(
      compileSvelteComponent(
        '<script lang="sverlin">let x = 1; yield "A";</script><script lang="sverlin" design>const x = 2;</script>'
      )
    ).rejects.toThrow('"x" is defined in the design block');
    await expect(
      compileSvelteComponent('<script lang="sverlin" input>const x = 1;</script><p>x</p>')
    ).rejects.toThrow('Add a <script lang="sverlin"> algorithm block');
  });

  it('reports algorithm errors at their authored line and column', async () => {
    const source =
      '<script lang="sverlin">\n  let x = 1;\n  yield "A";\n  x = missing;\n</script>\n<p>{x}</p>';
    await expect(compileSvelteComponent(source)).rejects.toMatchObject({
      name: 'InvalidSvelteSourceError',
      code: 'algorithm_error',
      line: 4,
      column: 7,
      message: expect.stringContaining('"missing" is not defined')
    });
  });

  it('keeps Svelte error positions after removing the algorithm block', async () => {
    await expect(
      compileSvelteComponent('<script lang="sverlin">\nyield "A";\n</script>\n\n{#if}')
    ).rejects.toMatchObject({ line: 5 });
  });

  it('requires exactly one algorithm block', async () => {
    await expect(compileSvelteComponent('<h1>Hi</h1>')).rejects.toThrow(
      'Add a <script lang="sverlin"> algorithm block'
    );
    await expect(
      compileSvelteComponent(
        '<script lang="sverlin">yield "A";</script><script lang="sverlin">yield "B";</script>'
      )
    ).rejects.toThrow('only one algorithm block');
  });

  it('injects the sverlin library components without authored imports', async () => {
    const result = await compileSvelteComponent(linearSearchSource);
    expect(result.javascript).toContain('sv-node');
    expect(result.javascript).toContain('sv-node');
    const withoutModuleScript = await compileSvelteComponent(
      '<script lang="sverlin">yield "Start";</script><Node>x</Node>'
    );
    expect(withoutModuleScript.labels).toEqual(['Start']);
    expect(withoutModuleScript.javascript).toContain('sv-node');
  });

  it('puts every recorded and design value in scope for a script-free view', async () => {
    const result = await compileSvelteComponent(
      '<script lang="sverlin" input>const values = [4, 9];</script>\n<script lang="sverlin">let total = 0; yield "Start"; for (const v of values) total += v; yield "Summed";</script>\n<script lang="sverlin" design>const accent = pick(["red"]);</script>\n<Node layout="column">{@const doubled = total * 2}<p style:color={accent}>{values.join("+")} = {total}; doubled {doubled}; step {step}, seed {seed}</p></Node>',
      5
    );
    expect(result.labels).toEqual(['Start', 'Summed']);
    expect(result.parameters).toEqual({ accent: 'red' });
  });

  it('rejects view scripts and values that shadow library components', async () => {
    await expect(
      compileSvelteComponent(
        '<script lang="sverlin">yield "A";</script>\n\n<script>const x = 1;</script>\n<p>{x}</p>'
      )
    ).rejects.toMatchObject({
      code: 'view_script',
      line: 3,
      message: expect.stringContaining('Views cannot have their own <script>')
    });
    await expect(
      compileSvelteComponent(
        '<script lang="sverlin">yield "A";</script><script module>const x = 1;</script>'
      )
    ).rejects.toThrow('Views cannot have their own <script>');
    await expect(
      compileSvelteComponent(
        '<script lang="sverlin">yield "A";</script>\n<script lang="sverlin" inputs>const x = 1;</script>'
      )
    ).rejects.toMatchObject({ code: 'sverlin_block', line: 2 });
    await expect(
      compileSvelteComponent('<script lang="sverlin">const Node = 1; yield "A";</script><p>x</p>')
    ).rejects.toThrow('"Node" names a library component');
  });

  it('renders nested arrays as nested nodes without an item snippet', async () => {
    const result = await compileSvelteComponent(
      '<script lang="sverlin" input>const grid = [[1, 2], [3, 4]];</script><script lang="sverlin">yield "A";</script><Node layout="column"><Node items={grid} layout="column" nested="row" /><Node items={[1, 2, 3, 4]} layout="grid" columns={2} /></Node>'
    );
    expect(result.javascript).toContain('sv-node');
  });

  it('embeds atomic types and registers renderer snippets named after types', async () => {
    const result = await compileSvelteComponent(
      '<script lang="sverlin" domain>const Int = type("integer"); const Height = type(Int, { unit: "cm" });</script><script lang="sverlin" input>const people = [Height(150), Height(170)];</script><script lang="sverlin">yield "A";</script>{#snippet Int(value, node)}<Node shape="circle" {value} {...node} />{/snippet}{#snippet helper(x)}{x}{/snippet}<Node items={people} />'
    );
    expect(result.javascript).toContain('people[1]');
    expect(result.javascript).toContain('sverlin:renderers');
  });

  it('rejects invalid domain blocks, renderers, and clashing names', async () => {
    await expect(
      compileSvelteComponent(
        '<script lang="sverlin">yield "A";</script>\n<script lang="sverlin" domain>\nconst A = type(Integer);\n</script>'
      )
    ).rejects.toMatchObject({
      code: 'algorithm_error',
      line: 3,
      message: expect.stringContaining('Unknown type Integer')
    });
    await expect(
      compileSvelteComponent(
        '<script lang="sverlin" domain>const Int = type("integer");</script><script lang="sverlin">yield "A";</script>\n{#snippet Int(value, node, extra)}{value}{/snippet}'
      )
    ).rejects.toMatchObject({
      code: 'type_renderer',
      line: 2,
      message: expect.stringContaining('at most (value, node)')
    });
    await expect(
      compileSvelteComponent(
        '<script lang="sverlin" domain>const Text = type("text");</script><script lang="sverlin">const Text = 1; yield "A";</script>'
      )
    ).rejects.toThrow('"Text" names an atomic type');
    await expect(
      compileSvelteComponent(
        '<script lang="sverlin" domain>const Node = type("integer");</script><script lang="sverlin">yield "A";</script>'
      )
    ).rejects.toThrow('"Node" names a library component');
  });

  it('rejects authored library imports', async () => {
    await expect(
      compileSvelteComponent('<script>import { Node } from "sverlin";</script><Node value={1} />')
    ).rejects.toThrow('cannot import');
  });

  it.each(['./package.json', 'esbuild/package.json', '/etc/hostname', 'svelte/../../package.json'])(
    'refuses to bundle require(%j) from the server file system',
    async (path) => {
      await expect(
        compileSvelteComponent(
          `<script lang="sverlin">yield "A";</script><p>{require(${JSON.stringify(path)})}</p>`
        )
      ).rejects.toMatchObject({
        name: 'InvalidSvelteSourceError',
        message: expect.stringContaining('cannot load module')
      });
    }
  );

  it('keeps authored line numbers after prelude injection', async () => {
    await expect(
      compileSvelteComponent('<script lang="sverlin">yield "A";</script>\n<p>\n{$state(1)}</p>')
    ).rejects.toMatchObject({ line: 3, column: 2 });
  });

  it('rejects ambiguous step labels before storing playback metadata', async () => {
    await expect(
      compileSvelteComponent(
        '<script lang="sverlin">yield "Same"; yield "Same";</script><h1>Hi</h1>'
      )
    ).rejects.toThrow('unique');
  });

  it('retains line and column for assistant source repair', async () => {
    await expect(compileSvelteComponent('<script>let = </script>')).rejects.toMatchObject({
      name: 'InvalidSvelteSourceError',
      line: 1,
      column: 9,
      code: 'js_parse_error'
    } satisfies Partial<InvalidSvelteSourceError>);
  });
});
