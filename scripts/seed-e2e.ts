/** Seed the principals required by browser tests from the active study definition. */

import { closeDatabase, database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import { activeStudyDefinition } from '$lib/shared/study/registry';

try {
  await database()
    .insert(schema.user)
    .values([
      {
        id: 'sverlin-e2e-admin',
        name: 'Sverlin E2E administrator',
        email: 'e2e-admin@sverlin.invalid',
        emailVerified: true,
        role: 'admin'
      },
      {
        id: 'sverlin-e2e-participant',
        name: 'E2E-GIFT',
        email: 'e2e-participant@sverlin.invalid',
        emailVerified: true,
        username: 'E2E-GIFT',
        role: 'user'
      }
    ]);
  await database().insert(schema.studyEnrollments).values({
    userId: 'sverlin-e2e-participant',
    studyId: activeStudyDefinition.id,
    studyVersion: activeStudyDefinition.version,
    armId: activeStudyDefinition.assignment.tieBreakOrder[0]
  });
} finally {
  await closeDatabase();
}
