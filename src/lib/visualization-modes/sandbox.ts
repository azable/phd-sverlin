/** Render executable artifacts in an opaque-origin iframe with a restrictive CSP. */

export function sandboxDocument(html: string, javascript: string, step = 0, seed = 1): string {
  const policy = [
    "default-src 'none'",
    "script-src 'unsafe-inline'",
    "style-src 'unsafe-inline'",
    'img-src data:',
    'font-src data:',
    "connect-src 'none'",
    "media-src 'none'",
    "object-src 'none'",
    "frame-src 'none'",
    "base-uri 'none'",
    "form-action 'none'"
  ].join('; ');
  const script =
    `window.__sverlinStep=${JSON.stringify(step)};window.__sverlinSeed=${JSON.stringify(seed)};\n${javascript}`.replace(
      /<\/script/giu,
      '<\\/script'
    );
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="${policy}"><style>html,body{width:100%;height:100%;margin:0;overflow:hidden;font-family:system-ui,sans-serif}</style></head><body><div id="app">${html}</div><script>${script}</script></body></html>`;
}
