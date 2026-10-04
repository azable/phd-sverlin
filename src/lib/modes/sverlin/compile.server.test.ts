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
      '<script lang="sverlin">yield "First"; yield "Second";</script><script>let { step = 0 } = $props();</script><h1>{step}</h1>'
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

  it('derives master steps from yield and keeps a seeded subset per presentation', async () => {
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
      expect(bundle.labels).toEqual(bundle.masterSteps.map((index) => master[index]));
      expect(bundle.masterSteps.at(0)).toBe(0);
      expect(bundle.masterSteps.at(-1)).toBe(master.length - 1);
      expect(bundle.masterSteps).toHaveLength(bundle.parameters.detail === 'coarse' ? 2 : 5);
      expect(['i', 'index']).toContain(bundle.parameters.pointerName);
    }
    expect(new Set(bundles.map(({ parameters }) => parameters.detail))).toEqual(
      new Set(['coarse', 'fine'])
    );
    expect(bundles[0].javascript).toContain('[3,8,5,2,7]');
    expect(bundles[0].javascript).not.toContain('yield optional(');
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
    await expect(
      compileSvelteComponent('<script module>export const steps = ["A"];</script><h1>Hi</h1>')
    ).rejects.toThrow('Add a <script lang="sverlin"> algorithm block');
    await expect(
      compileSvelteComponent(
        '<script lang="sverlin">yield "A";</script><script lang="sverlin">yield "B";</script>'
      )
    ).rejects.toThrow('only one algorithm block');
  });

  it('injects the sverlin library components without authored imports', async () => {
    const result = await compileSvelteComponent(linearSearchSource);
    expect(result.javascript).toContain('sv-stage');
    expect(result.javascript).toContain('sv-array');
    const withoutModuleScript = await compileSvelteComponent(
      '<script lang="sverlin">yield "Start";</script><Stage title="Hi">x</Stage>'
    );
    expect(withoutModuleScript.labels).toEqual(['Start']);
    expect(withoutModuleScript.javascript).toContain('sv-stage');
  });

  it('rejects authored library imports', async () => {
    await expect(
      compileSvelteComponent('<script>import { Stage } from "sverlin";</script><Stage title="x" />')
    ).rejects.toThrow('cannot import');
  });

  it.each(['./package.json', 'esbuild/package.json', '/etc/hostname', 'svelte/../../package.json'])(
    'refuses to bundle require(%j) from the server file system',
    async (path) => {
      await expect(
        compileSvelteComponent(
          `<script lang="sverlin">yield "A";</script><script>const p = require(${JSON.stringify(path)});</script>{p}`
        )
      ).rejects.toMatchObject({
        name: 'InvalidSvelteSourceError',
        message: expect.stringContaining('cannot load module')
      });
    }
  );

  it('keeps authored line numbers after prelude injection', async () => {
    await expect(
      compileSvelteComponent(
        '<script lang="sverlin">yield "A";</script>\n<script module>\nconst a = 1;\n</script>\n<script>\nlet { b } = $props();\nlet { c } = $props();\n</script>'
      )
    ).rejects.toMatchObject({ line: 7 });
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
