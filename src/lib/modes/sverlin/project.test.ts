import { describe, expect, it } from 'vitest';

import { projectSnapshotAt } from '$lib/shared/projects/projection';
import { MemoryProjectRepository } from '$lib/server/projects/memory-repository.test-support';
import { alignPresentationFrames, presentationStepLabels } from '$lib/shared/presentations';
import { appendProjectPreference } from '$lib/server/projects/presentations';
import { linearSearchSource } from './contract';
import {
  createProjectSkeleton,
  buildProjectPresentations,
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
      '<script lang="sverlin">yield "First"; yield "Second";</script><script>let { step = 0 } = $props();</script><h1>{step}</h1>';
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

    const rebuilt = await buildProjectPresentations(
      {
        projectId: created.projectId,
        expectedHead: result.document.events.length,
        seed: 42,
        purpose: 'seed-change',
        operationId: crypto.randomUUID()
      },
      dependencies
    );
    expect(rebuilt.appendedEvents.some((event) => event.type === 'visualization.presented')).toBe(
      true
    );
  });

  it('records seeded step subsets of one master trace as an aligned display set', async () => {
    const repository = new MemoryProjectRepository();
    const dependencies: ProjectServiceDependencies = { repository };
    const { document: created } = await createProjectSkeleton({}, dependencies);
    const artifact = projectSnapshotAt(created).artifacts.main;
    let result;
    let presentations;
    // Seeds are random; half of pairs differ in detail, so 30 rebuilds make a miss negligible.
    for (let attempt = 0; attempt < 30; attempt++) {
      result = await updateProjectArtifact(
        {
          projectId: created.projectId,
          expectedHead: (result?.document ?? created).events.length,
          artifactId: artifact.artifactId,
          source: `${linearSearchSource}\n<!-- attempt ${attempt} -->`,
          presentationCount: 2,
          operationId: crypto.randomUUID()
        },
        dependencies
      );
      presentations = result.appendedEvents.flatMap((event) =>
        event.type === 'visualization.presented' ? [event.payload.presentation] : []
      );
      const [first, second] = presentations.map(presentationStepLabels);
      if (first.length !== second.length) break;
    }
    if (!result || !presentations) throw new Error('No presentations were built.');
    const [left, right] = presentations;
    expect(left.format === 'browser-bundle-v1' && right.format === 'browser-bundle-v1').toBe(true);
    if (left.format !== 'browser-bundle-v1' || right.format !== 'browser-bundle-v1') return;
    expect(left.stepSignature).toBe(right.stepSignature);
    expect(left.labels).not.toEqual(right.labels);
    expect(left.parameters?.detail).not.toBe(right.parameters?.detail);
    const frames = alignPresentationFrames([left, right]);
    expect(frames).toHaveLength(5);
    const document = await appendProjectPreference(
      result.document,
      {
        presentations: [left.presentationId, right.presentationId],
        preferred: left.presentationId,
        step: frames.length - 2,
        operationId: crypto.randomUUID()
      },
      dependencies
    );
    expect(document.events.at(-1)?.type).toBe('visualization.preference-recorded');
  });
});
