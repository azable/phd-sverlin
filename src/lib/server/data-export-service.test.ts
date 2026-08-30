import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, describe, expect, it, vi } from 'vitest';

import type { ExportDataSource, ExportSnapshot } from './data-export';
import { resolveDataExport, writeSelectedDataDirectory } from './data-export-service';

const temporaryRoots: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryRoots.splice(0).map((root) => rm(root, { recursive: true, force: true }))
  );
});

describe('canonical data export service', () => {
  it('uses the same project, study, and participant scope vocabulary as the admin interface', async () => {
    await expect(resolveDataExport({ type: 'projects' })).resolves.toEqual({
      scope: { type: 'projects' },
      filenameLabel: 'all-projects'
    });
    await expect(
      resolveDataExport({ type: 'study', studyId: 'pilot-study', studyVersion: 1 })
    ).resolves.toEqual({
      scope: { type: 'study', studyId: 'pilot-study', studyVersion: 1 },
      filenameLabel: 'study-pilot-study-v1'
    });
    const resolveParticipant = vi.fn(async () => ({
      userId: 'user-2',
      participantId: '02'
    }));
    await expect(
      resolveDataExport(
        { type: 'participant', participant: { type: 'participant-id', value: '02' } },
        resolveParticipant as never
      )
    ).resolves.toEqual({
      scope: { type: 'participant', userId: 'user-2' },
      filenameLabel: 'participant-02'
    });
  });

  it('writes the canonical export tree with one frozen timestamp and lifecycle guard', async () => {
    const root = await mkdtemp(path.join(tmpdir(), 'sverlin-export-service-test-'));
    temporaryRoots.push(root);
    const source: ExportDataSource = {
      collect: vi.fn(async () => emptySnapshot()),
      readResource: vi.fn()
    };
    const assertIdle = vi.fn(async () => undefined);
    const exportedAt = '2026-08-30T12:00:00.000Z';

    const manifest = await writeSelectedDataDirectory(
      path.join(root, 'export'),
      { type: 'projects' },
      { exportedAt },
      {
        source,
        assertIdle,
        resolveParticipant: vi.fn() as never
      }
    );

    expect(manifest).toMatchObject({
      scope: { type: 'projects' },
      exportedAt,
      projectCount: 0
    });
    expect(assertIdle).toHaveBeenCalledWith({ type: 'projects' });
    expect(source.collect).toHaveBeenCalledWith({ type: 'projects' });
  });
});

function emptySnapshot(): ExportSnapshot {
  return {
    owners: [],
    participants: [],
    projects: [],
    study: { definitions: [], enrollments: [], runs: [], phases: [], flows: [] }
  };
}
