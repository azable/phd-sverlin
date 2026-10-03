/** Authored source starter for the script-free HTML-frame mode. */

export const htmlStarter = {
  path: 'Visualization.html.json',
  language: 'json',
  mediaType: 'application/vnd.sverlin.html-frames+json',
  source: JSON.stringify({
    format: 'sverlin-html-frames',
    version: 1,
    frames: [
      {
        label: 'Start',
        html: '<main><h1>Start your visualization</h1><p>Describe what you would like to create in the timeline.</p></main>'
      }
    ]
  })
} as const;
