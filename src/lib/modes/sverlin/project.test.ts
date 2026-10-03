import { describe, expect, it } from 'vitest';

import { projectSnapshotAt } from '$lib/shared/projects/projection';
import { MemoryProjectRepository } from '$lib/server/projects/memory-repository.test-support';
import {
  createProjectSkeleton,
  renderProject,
  updateProjectArtifact,
  type ProjectServiceDependencies
} from '$lib/server/projects/service';

describe('Svelte-backed project lifecycle', () => {
  it('records a bundled presentation and step labels from one edited component', async () => {
    const repository = new MemoryProjectRepository();
    const dependencies: ProjectServiceDependencies = { repository };
    const { document: created } = await createProjectSkeleton({}, dependencies);
    const artifact = projectSnapshotAt(created).artifacts.main;
    expect(artifact.path).toBe('Main.svelte');
    const source =
      '<script module>export const steps = ["First", "Second"];</script><script>let { step = 0 } = $props();</script><h1>{step}</h1>';
    const result = await updateProjectArtifact(
      {
        projectId: created.projectId,
        expectedHead: created.events.length,
        artifactId: artifact.artifactId,
        source,
        presentationCount: 2,
        operationId: crypto.randomUUID()
      },
      dependencies
    );
    const presentations = result.appendedEvents.flatMap((event) =>
      event.type === 'visualization.presented' ? [event.payload.presentation] : []
    );
    expect(presentations).toHaveLength(2);
    expect(presentations.every((presentation) => presentation.format === 'browser-bundle-v1')).toBe(
      true
    );
    expect(presentations[0]).toMatchObject({ mode: 'sverlin', labels: ['First', 'Second'] });

    const rerender = await renderProject(
      {
        projectId: created.projectId,
        expectedHead: result.document.events.length,
        seed: 42,
        operationId: crypto.randomUUID()
      },
      dependencies
    );
    expect(rerender.appendedEvents.some((event) => event.type === 'visualization.presented')).toBe(
      true
    );
  });
});
