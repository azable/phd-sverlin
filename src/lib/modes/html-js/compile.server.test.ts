import { describe, expect, it } from 'vitest';

import { compileHtmlJs } from './compile.server';

describe('HTML/JS packaging', () => {
  it('sanitizes active markup and keeps separately authored script', async () => {
    const result = await compileHtmlJs({
      format: 'html-js-v1',
      html: '<h1 onclick="alert(1)">Hello</h1><script>evil()</script>',
      javascript: 'document.querySelector("h1").textContent = "Ready";'
    });
    expect(result.html).toBe('<h1>Hello</h1>');
    expect(result.javascript).toContain('Ready');
  });

  it('rejects static and dynamic imports, including computed targets', async () => {
    for (const javascript of [
      'import x from "x";',
      'import("x")',
      'import(window.target)',
      'export const x = 1'
    ]) {
      await expect(
        compileHtmlJs({ format: 'html-js-v1', html: '<h1>Safe</h1>', javascript })
      ).rejects.toThrow('cannot import or export');
    }
  });
});
