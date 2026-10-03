/** One developer-registered catalogue of visualization modes and their owned assistants. */

import { sverlinStarter } from './sverlin/contract';
import { htmlStarter } from './html/contract';
import { htmlJsStarter } from './html-js/contract';

export const modeCatalog = {
  sverlin: {
    assistantId: 'sverlin-assistant',
    authoring: 'source',
    scriptedPlayback: true,
    title: 'Sverlin',
    starter: sverlinStarter
  },
  html: {
    assistantId: 'html-assistant',
    authoring: 'candidates',
    scriptedPlayback: false,
    title: 'HTML frames',
    starter: htmlStarter
  },
  'html-js': {
    assistantId: 'html-js-assistant',
    authoring: 'candidates',
    scriptedPlayback: true,
    title: 'HTML + JavaScript',
    starter: htmlJsStarter
  }
} as const;
