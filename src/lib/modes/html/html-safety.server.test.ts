import { describe, expect, it } from 'vitest';

import { htmlFrameSourceDocument, validateHtmlFramesManifest } from './html-safety.server';

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

  it.each([
    '<div style="background:url(https://example.com/a.png)">x</div>',
    '<div style="background:url(\'//example.com/a.png\')">x</div>',
    '<style>.a{background:url(https://example.com/a.png</style>'
  ])('rejects remote CSS urls', (html) => {
    expect(() => validateHtmlFramesManifest(manifest(html))).toThrow(/remote/i);
  });

  it('keeps inline image urls', () => {
    const result = validateHtmlFramesManifest(
      manifest('<div style="background:url(\'data:image/png;base64,AAAA\')">x</div>')
    );
    expect(result.rendered.frames[0].html).toContain('data:image/png');
  });

  it('rejects many unclosed url( openings in linear time', () => {
    const start = performance.now();
    expect(() => validateHtmlFramesManifest(manifest('url('.repeat(120 * 1024)))).toThrow(
      /remote/i
    );
    expect(performance.now() - start).toBeLessThan(1000);
  });

  it('wraps fragments in a script- and network-denying policy', () => {
    const document = htmlFrameSourceDocument('<p>Safe</p>');
    expect(document).toContain("default-src 'none'");
    expect(document).toContain("script-src 'none'");
  });
});
