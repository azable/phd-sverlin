import { describe, expect, it } from 'vitest';

import { projectSnapshotAt } from '$lib/shared/projects/projection';
import { MemoryProjectRepository } from '$lib/server/projects/memory-repository.test-support';
import {
  createProjectSkeleton,
  updateProjectArtifact,
  type ProjectServiceDependencies
} from '$lib/server/projects/service';

describe('free-form HTML/JS project', () => {
  it('stores source separately from sanitized HTML and isolated JavaScript', async () => {
    const repository = new MemoryProjectRepository();
    const dependencies: ProjectServiceDependencies = { repository };
    const { document } = await createProjectSkeleton(
      { creation: { templateId: 'blank', mode: 'html-js' } },
      dependencies
    );
    const artifact = projectSnapshotAt(document).artifacts.main;
    expect(artifact.path).toBe('Visualization.html-js.json');
    const source = JSON.stringify({
      format: 'html-js-v1',
      html: '<h1 onclick="attack()">Safe</h1>',
      javascript: 'document.querySelector("h1").textContent = "Ready";'
    });
    const updated = await updateProjectArtifact(
      {
        projectId: document.projectId,
        expectedHead: document.events.length,
        artifactId: artifact.artifactId,
        source,
        presentationCount: 1,
        operationId: crypto.randomUUID()
      },
      dependencies
    );
    const presented = updated.appendedEvents.find(
      (event) => event.type === 'visualization.presented'
    );
    expect(presented?.type).toBe('visualization.presented');
    if (
      presented?.type !== 'visualization.presented' ||
      presented.payload.presentation.format !== 'browser-bundle-v1'
    )
      throw new Error('Expected browser bundle');
    expect(presented.payload.presentation.html.text).toBe('<h1>Safe</h1>');
    expect(presented.payload.presentation.javascript.text).toContain('Ready');
    expect(projectSnapshotAt(updated.document).artifacts.main.content.text).toBe(source);
  });
});
