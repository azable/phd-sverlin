import { describe, expect, it } from 'vitest';

import { sandboxDocument } from './sandbox';

describe('isolated browser document', () => {
  it('escapes script terminators and denies network-capable resource directives', () => {
    const document = sandboxDocument(
      '<h1>Hi</h1>',
      'const value = "</script><img src=https://example.com/leak>";',
      2,
      7
    );
    expect(document).not.toContain('</script><img');
    expect(document).toContain('<\\/script><img');
    expect(document).toContain("connect-src 'none'");
    expect(document).toContain("default-src 'none'");
    expect(document).toContain("form-action 'none'");
    expect(document).toContain('window.__sverlinStep=2;window.__sverlinSeed=7');
  });
});
