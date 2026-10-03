/** Authored source starter for the separately scripted HTML/JS mode. */

export const htmlJsStarter = {
  path: 'Visualization.html-js.json',
  language: 'json',
  mediaType: 'application/json',
  source: JSON.stringify(
    {
      format: 'html-js-v1',
      html: '<main><h1>Start your visualization</h1></main>',
      javascript: ''
    },
    null,
    2
  )
} as const;
