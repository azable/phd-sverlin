import { createHash } from 'node:crypto';

import { describe, expect, it, vi } from 'vitest';

import {
  verifyExportResource,
  writeDataExport,
  type ExportDataSource,
  type ExportSink,
  type ExportSnapshot
} from './data-export';

describe('project data export traversal', () => {
  it('writes one canonical, resource-verified tree without authentication data', async () => {
    const bytes = Buffer.from('project resource');
    const digest = createHash('sha256').update(bytes).digest('hex');
    const snapshot = fixtureSnapshot(digest, bytes.byteLength);
    const files = new Map<string, Uint8Array>();
    const sink: ExportSink = {
      write(pathname, value) {
        files.set(pathname, Uint8Array.from(value));
      }
    };
    const source: ExportDataSource = {
      collect: vi.fn(async () => snapshot),
      readResource: vi.fn(async () => bytes)
    };

    const manifest = await writeDataExport(
      source,
      sink,
      { type: 'projects', projectId: 'project-test' },
      '2026-08-30T12:00:00.000Z'
    );

    expect([...files.keys()]).toEqual([
      'owners.json',
      'participants.json',
      'study/definitions.json',
      'study/enrollments.json',
      'study/runs.json',
      'study/phases.json',
      'study/flows.json',
      'projects/project-test/project.json',
      'projects/project-test/resources.json',
      `projects/project-test/resources/sha256-${digest}`,
      'manifest.json'
    ]);
    expect(manifest).toMatchObject({
      scope: { type: 'projects', projectId: 'project-test' },
      ownerCount: 1,
      projectCount: 1
    });
    expect(manifest.files).toHaveLength(10);
    expect(JSON.parse(Buffer.from(files.get('owners.json')!).toString())).toEqual([
      { id: 'owner-1', label: 'P001', role: 'user', enabled: true }
    ]);
    expect(Buffer.from(files.get('owners.json')!).toString()).not.toContain('@');
    expect(source.collect).toHaveBeenCalledWith({
      type: 'projects',
      projectId: 'project-test'
    });
    expect(source.readResource).toHaveBeenCalledWith('project-test', `sha256-${digest}`);
  });

  it('rejects substituted resource bytes before completing an export', () => {
    const digest = createHash('sha256').update('expected').digest('hex');
    expect(() =>
      verifyExportResource(Buffer.from('wrong'), {
        resourceId: `sha256-${digest}`,
        sha256: digest,
        byteLength: Buffer.byteLength('expected')
      })
    ).toThrow(/byte length|SHA-256/);
  });
});

function fixtureSnapshot(digest: string, byteLength: number): ExportSnapshot {
  return {
    owners: [{ id: 'owner-1', label: 'P001', role: 'user', enabled: true }],
    projects: [
      {
        id: 'project-test',
        ownerUserId: 'owner-1',
        title: 'Project export fixture',
        templateId: 'blank',
        renderer: 'sverlin',
        createdAt: '2026-08-30T10:00:00.000Z',
        updatedAt: '2026-08-30T11:00:00.000Z',
        document: {
          schemaVersion: 2,
          projectId: 'project-test',
          events: [
            {
              id: 1,
              type: 'project.created',
              actor: { kind: 'user' },
              operationId: '12345678-1234-4123-8123-123456789abc',
              createdAt: '2026-08-30T10:00:00.000Z',
              payload: {
                title: 'Project export fixture',
                entryArtifactId: 'dsl-main',
                creation: { templateId: 'blank' }
              }
            }
          ]
        },
        resources: [
          {
            projectId: 'project-test',
            resourceId: `sha256-${digest}`,
            sha256: digest,
            byteLength,
            mediaType: 'application/octet-stream',
            createdAt: '2026-08-30T11:00:00.000Z'
          }
        ]
      }
    ],
    participants: [],
    study: { definitions: [], enrollments: [], runs: [], phases: [], flows: [] }
  };
}
