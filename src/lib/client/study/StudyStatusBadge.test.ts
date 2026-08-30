import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';

import StudyStatusBadge from './StudyStatusBadge.svelte';
import { studyStatusSurfaceClasses } from './study-status';

describe('StudyStatusBadge', () => {
  it.each([
    ['not-started', 'Not started', 'bg-muted', 'bg-muted/50'],
    ['in-progress', 'In progress', 'bg-status-info', 'bg-status-info/50'],
    ['ready-to-continue', 'Ready', 'bg-status-warning', 'bg-status-warning/50'],
    ['completed', 'Completed', 'bg-status-success', 'bg-status-success/50']
  ] as const)('renders %s with its semantic color', (status, label, colorClass, surfaceClass) => {
    const { body } = render(StudyStatusBadge, { props: { status } });

    expect(body).toContain(label);
    expect(body).toContain(colorClass);
    expect(studyStatusSurfaceClasses[status]).toBe(surfaceClass);
  });
});
