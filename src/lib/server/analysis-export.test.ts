import { createHash } from 'node:crypto';

import { describe, expect, it, vi } from 'vitest';

import {
  verifyAnalysisResource,
  writeAnalysisExport,
  type AnalysisDataSource,
  type AnalysisExportSink,
  type AnalysisSnapshot
} from './analysis-export';

describe('analysis export traversal', () => {
  it('writes one canonical, resource-verified tree without authentication data', async () => {
    const bytes = Buffer.from('analysis resource');
    const digest = createHash('sha256').update(bytes).digest('hex');
    const snapshot = fixtureSnapshot(digest, bytes.byteLength);
    const files = new Map<string, Uint8Array>();
    const sink: AnalysisExportSink = {
      write(pathname, value) {
        files.set(pathname, Uint8Array.from(value));
      }
    };
    const source: AnalysisDataSource = {
      collect: vi.fn(async () => snapshot),
      readResource: vi.fn(async () => bytes)
    };

    const manifest = await writeAnalysisExport(source, sink, {
      projectId: 'analysis-project',
      exportedAt: '2026-08-30T12:00:00.000Z'
    });

    expect([...files.keys()]).toEqual([
      'owners.json',
      'projects/analysis-project/project.json',
      'projects/analysis-project/resources.json',
      `projects/analysis-project/resources/sha256-${digest}`,
      'manifest.json'
    ]);
    expect(manifest).toMatchObject({
      scope: { type: 'project', projectId: 'analysis-project' },
      ownerCount: 1,
      projectCount: 1
    });
    expect(manifest.files).toHaveLength(4);
    expect(JSON.parse(Buffer.from(files.get('owners.json')!).toString())).toEqual([
      { id: 'owner-1', label: 'P001', role: 'user', enabled: true }
    ]);
    expect(Buffer.from(files.get('owners.json')!).toString()).not.toContain('@');
    expect(source.collect).toHaveBeenCalledWith('analysis-project');
    expect(source.readResource).toHaveBeenCalledWith('analysis-project', `sha256-${digest}`);
  });

  it('rejects substituted resource bytes before completing an export', () => {
    const digest = createHash('sha256').update('expected').digest('hex');
    expect(() =>
      verifyAnalysisResource(Buffer.from('wrong'), {
        resourceId: `sha256-${digest}`,
        sha256: digest,
        byteLength: Buffer.byteLength('expected')
      })
    ).toThrow(/byte length|SHA-256/);
  });
});

function fixtureSnapshot(digest: string, byteLength: number): AnalysisSnapshot {
  return {
    owners: [{ id: 'owner-1', label: 'P001', role: 'user', enabled: true }],
    projects: [
      {
        id: 'analysis-project',
        ownerUserId: 'owner-1',
        title: 'Analysis project',
        templateId: 'blank',
        createdAt: '2026-08-30T10:00:00.000Z',
        updatedAt: '2026-08-30T11:00:00.000Z',
        document: {
          schemaVersion: 1,
          projectId: 'analysis-project',
          events: [
            {
              id: 1,
              type: 'project.created',
              actor: { kind: 'user' },
              operationId: '12345678-1234-4123-8123-123456789abc',
              createdAt: '2026-08-30T10:00:00.000Z',
              payload: { title: 'Analysis project', entryArtifactId: 'dsl-main' }
            }
          ]
        },
        resources: [
          {
            projectId: 'analysis-project',
            resourceId: `sha256-${digest}`,
            sha256: digest,
            byteLength,
            mediaType: 'application/octet-stream',
            createdAt: '2026-08-30T11:00:00.000Z'
          }
        ]
      }
    ]
  };
}
