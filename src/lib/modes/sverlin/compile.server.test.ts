import { describe, expect, it } from 'vitest';

import { compileSvelteComponent, InvalidSvelteSourceError } from './compile.server';
import { linearSearchSource } from './contract';

describe('single-component Svelte compilation', () => {
  it('bundles a component and its playback input without executing it', async () => {
    const result = await compileSvelteComponent(
      '<script module>export const steps = ["First", "Second"];</script><script>let { step = 0 } = $props();</script><h1>{step}</h1>'
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
      compileSvelteComponent(
        '<script module>export const steps = ["A"]; import x from "other";</script><h1>{x}</h1>'
      )
    ).rejects.toThrow('cannot import');
    await expect(
      compileSvelteComponent('<script>const x = import("/secret")</script><h1>{x}</h1>')
    ).rejects.toThrow('cannot import');
    await expect(compileSvelteComponent('<h1>{import(window.target)}</h1>')).rejects.toThrow(
      'cannot import'
    );
  });

  it('injects the sverlin library components without authored imports', async () => {
    const result = await compileSvelteComponent(linearSearchSource);
    expect(result.labels).toEqual(['Start', 'Compare', 'Result']);
    expect(result.javascript).toContain('sv-stage');
    expect(result.javascript).toContain('sv-array');
    const withoutModuleScript = await compileSvelteComponent('<Stage title="Hi">x</Stage>');
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
        compileSvelteComponent(`<script>const p = require(${JSON.stringify(path)});</script>{p}`)
      ).rejects.toMatchObject({
        name: 'InvalidSvelteSourceError',
        message: expect.stringContaining('cannot load module')
      });
    }
  );

  it('keeps authored line numbers after prelude injection', async () => {
    await expect(
      compileSvelteComponent('<script module>\nexport const steps = ["A"];\n</script>\n{#if}')
    ).rejects.toMatchObject({ line: 4 });
  });

  it('rejects ambiguous step labels before storing playback metadata', async () => {
    await expect(
      compileSvelteComponent(
        '<script module>export const steps = ["Same", "Same"];</script><h1>Hi</h1>'
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
