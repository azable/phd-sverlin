/** Page theme for every presentation: colour tokens, the canvas, and the page's own layout. */

export const themeCss = `
:root {
  --sv-ink: #172033;
  --sv-muted: #5d6880;
  --sv-line: #d7deea;
  --sv-surface: #ffffff;
  --sv-canvas: #f6f8fb;
  --sv-amber: #fef3c7;
  --sv-amber-line: #d4a72c;
  --sv-blue: #e8f0fe;
  --sv-blue-line: #7aa5ea;
  --sv-green: #e3f7ec;
  --sv-green-line: #3caf78;
  --sv-red: #fde8e8;
  --sv-red-line: #d9534f;
  --sv-purple: #f1e8fd;
  --sv-purple-line: #8b5cf6;
  --sv-radius: 10px;
  font-family: system-ui, sans-serif;
}
body {
  margin: 0;
  background: var(--sv-canvas);
  color: var(--sv-ink);
}
#app {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 1.5rem;
  box-sizing: border-box;
  max-width: 960px;
  margin: 0 auto;
  padding: 2rem;
}
`;
