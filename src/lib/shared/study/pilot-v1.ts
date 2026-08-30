/** Initial counterbalanced Sverlin-versus-HTML study protocol. */

import { defineStudy, minutes } from './definition';

export const pilotStudyV1 = defineStudy({
  id: 'pilot-study',
  version: 1,
  name: 'Pilot study',
  description: 'Counterbalanced comparison of Sverlin and HTML visualization workflows.',
  assignment: {
    strategy: 'balanced',
    tieBreakOrder: ['sverlin-first', 'html-first']
  },
  conditions: {
    sverlin: {
      renderer: 'sverlin',
      // Keep two comparison pairs ready: one visible pair and one ahead-of-time pair.
      presentationBufferTarget: 4,
      workspace: { view: 'participant', layout: 'comparison', artifactEditor: 'collapsible' },
      project: { templateId: 'blank' },
      durationSeconds: minutes(15)
    },
    html: {
      renderer: 'html',
      workspace: { view: 'participant', layout: 'single', artifactEditor: 'collapsible' },
      project: { templateId: 'blank', artifactFormat: 'html-frames-json' },
      durationSeconds: minutes(15)
    }
  },
  arms: {
    'sverlin-first': { slots: { first: 'sverlin', second: 'html' } },
    'html-first': { slots: { first: 'html', second: 'sverlin' } }
  },
  flow: [
    {
      id: 'welcome',
      kind: 'instruction',
      title: 'Welcome',
      paragraphs: [
        'You will complete two visualization tasks.',
        'Each task lasts 15 minutes and uses a different visualization system.'
      ],
      continueLabel: 'Begin first task'
    },
    {
      id: 'task-one',
      kind: 'task',
      conditionSlot: 'first',
      instructions: {
        title: 'Visualization task',
        prompt: 'Create and refine a visualization for the supplied task.'
      }
    },
    {
      id: 'between-tasks',
      kind: 'instruction',
      title: 'First task complete',
      paragraphs: [
        'The next task uses a different visualization system.',
        'Your first project is now locked.'
      ],
      continueLabel: 'Begin second task'
    },
    {
      id: 'task-two',
      kind: 'task',
      conditionSlot: 'second',
      instructions: {
        title: 'Visualization task',
        prompt: 'Create and refine a visualization for the supplied task.'
      }
    },
    {
      id: 'complete',
      kind: 'completion',
      title: 'Study complete',
      paragraphs: ['Thank you. Your responses have been recorded.']
    }
  ]
});
