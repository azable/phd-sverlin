/** Seed the principals and exact participant study run required by browser tests. */

import { closeDatabase, database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import { pilotStudyV1 } from '$lib/shared/study/pilot-v1';

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
  const [run] = await database()
    .insert(schema.studyRuns)
    .values({
      mode: 'participant',
      ownerUserId: 'sverlin-e2e-participant',
      studyId: pilotStudyV1.id,
      studyVersion: pilotStudyV1.version,
      armId: pilotStudyV1.assignment.tieBreakOrder[0]!
    })
    .returning({ id: schema.studyRuns.id });
  if (!run) throw new Error('The E2E participant study run could not be created.');
  await database().insert(schema.studyEnrollments).values({
    userId: 'sverlin-e2e-participant',
    runId: run.id
  });
} finally {
  await closeDatabase();
}
