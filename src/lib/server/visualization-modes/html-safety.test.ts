import { describe, expect, it } from 'vitest';

import { htmlFrameSourceDocument, validateHtmlFramesManifest } from './html-safety';

const manifest = (html: string) => ({
  format: 'sverlin-html-frames' as const,
  version: 1 as const,
  frames: [{ label: 'Overview', html }]
});

describe('HTML frame safety', () => {
  it('retains static HTML, inline CSS, and SVG', () => {
    const result = validateHtmlFramesManifest(
      manifest(
        '<style>.bar{fill:#09f}</style><main><svg viewBox="0 0 10 10"><rect class="bar" width="10" height="4"></rect></svg></main>'
      )
    );
    expect(result.rendered.frames[0].html).toContain('<svg');
    expect(result.rendered.frames[0].html).toContain('<style>');
  });

  it.each([
    '<script>alert(1)</script>',
    '<img src="https://example.com/tracker.png">',
    '<button onclick="alert(1)">Run</button>',
    '<style>@import "https://example.com/style.css"</style>'
  ])('rejects active or network-capable markup', (html) => {
    expect(() => validateHtmlFramesManifest(manifest(html))).toThrow(/static|remote/i);
  });

  it('wraps fragments in a script- and network-denying policy', () => {
    const document = htmlFrameSourceDocument('<p>Safe</p>');
    expect(document).toContain("default-src 'none'");
    expect(document).toContain("script-src 'none'");
  });
});
