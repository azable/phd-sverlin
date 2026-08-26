import { listProjectTemplates } from '$lib/server/projects/starter-catalog';

import type { PageServerLoad } from './$types';

/** Supply immutable project-template metadata to the creation dialog. */
export const load: PageServerLoad = () => ({ templates: listProjectTemplates() });
