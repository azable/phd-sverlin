import { describe, expect, it } from 'vitest';

import { projectSnapshotAt } from '$lib/shared/projects/projection';
import { MemoryProjectRepository } from '$lib/server/projects/memory-repository.test-support';
import {
  createProjectSkeleton,
  updateProjectArtifact,
  type ProjectServiceDependencies
} from '$lib/server/projects/service';

describe('script-free HTML source edits', () => {
  it('uses the shared save command and rejects script markup before committing an artifact', async () => {
    const repository = new MemoryProjectRepository();
    const dependencies: ProjectServiceDependencies = { repository };
    const { document } = await createProjectSkeleton(
      { creation: { templateId: 'blank', renderer: 'html' } },
      dependencies
    );
    const artifact = projectSnapshotAt(document).artifacts['dsl-main'];
    const operation = {
      projectId: document.projectId,
      expectedHead: document.events.length,
      artifactId: artifact.artifactId,
      presentationCount: 1 as const,
      operationId: crypto.randomUUID()
    };
    await expect(
      updateProjectArtifact(
        {
          ...operation,
          source: JSON.stringify({
            format: 'sverlin-html-frames',
            version: 1,
            frames: [{ label: 'Start', html: '<script>attack()</script>' }]
          })
        },
        dependencies
      )
    ).rejects.toThrow('static');
    expect((await repository.load(document.projectId)).events).toHaveLength(document.events.length);
    const saved = await updateProjectArtifact(
      {
        ...operation,
        source: JSON.stringify({
          format: 'sverlin-html-frames',
          version: 1,
          frames: [{ label: 'Start', html: '<main>Safe</main>' }]
        })
      },
      dependencies
    );
    expect(saved.appendedEvents.some((event) => event.type === 'visualization.presented')).toBe(
      true
    );
  });
});
