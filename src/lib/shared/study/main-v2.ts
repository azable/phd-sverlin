/** New two-condition study; historical enrollments remain tied to version one. */

import { defineStudy } from './definition';
import { mainStudyV1 } from './main-v1';

export const mainStudyV2 = defineStudy({
  ...mainStudyV1,
  version: 2,
  description: 'Counterbalanced comparison of single-component Svelte and static HTML frames.',
  conditions: {
    ...mainStudyV1.conditions,
    sverlin: {
      ...mainStudyV1.conditions.sverlin,
      project: { templateId: 'blank', artifactFormat: 'svelte-component' }
    }
  }
});
