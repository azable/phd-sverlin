import { afterEach, describe, expect, it, vi } from 'vitest';

import { mainStudyV1 } from '$lib/shared/study/main-v1';

import type { InteractionOutbox } from './interaction-outbox';
import { ProjectInteractionRecorder } from './interaction-recorder';

describe('project interaction recorder isolation', () => {
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it('does not surface outbox or transport failures to workspace calls', async () => {
    vi.useFakeTimers();
    const browserDocument = Object.assign(new EventTarget(), {
      visibilityState: 'visible',
      hasFocus: () => true
    });
    const browserWindow = new EventTarget();
    vi.stubGlobal('document', browserDocument);
    vi.stubGlobal('window', browserWindow);
    vi.stubGlobal('innerWidth', 1280);
    vi.stubGlobal('innerHeight', 720);
    vi.stubGlobal('devicePixelRatio', 1);
    const failure = async () => {
      throw new Error('telemetry unavailable');
    };
    const outbox: InteractionOutbox = {
      putSession: vi.fn(failure),
      markStopped: vi.fn(failure),
      putEvent: vi.fn(failure),
      sessions: vi.fn(failure),
      events: vi.fn(failure),
      acknowledge: vi.fn(failure),
      abandon: vi.fn(failure)
    };
    const recorder = new ProjectInteractionRecorder({
      projectId: 'project-one',
      capture: mainStudyV1.interactionCapture!,
      applicationVersion: 'test',
      outbox,
      fetch: vi.fn(async () => {
        throw new Error('offline');
      })
    });
    const root = new EventTarget() as HTMLElement;

    expect(() => {
      recorder.start(root);
      recorder.recordWorkspaceState({
        projectHead: 1,
        connection: 'open',
        atHead: true,
        layout: 'single',
        visiblePresentationIds: [],
        followingLatestPresentations: true,
        focusedTimelineEvents: [],
        visualSelections: [],
        viewports: [],
        draft: { hasContent: false, characterCount: 0, referenceCount: 0, focused: false },
        document: {
          visibility: 'visible',
          focused: true,
          viewport: { width: 1280, height: 720, devicePixelRatio: 1 }
        }
      });
      recorder.recordDraft([{ type: 'markdown', text: 'draft' }], true);
      vi.advanceTimersByTime(1);
      recorder.stop();
    }).not.toThrow();
    await Promise.resolve();
    await Promise.resolve();

    expect(outbox.putSession).toHaveBeenCalled();
  });

  it('does not record observations after the independent capture deadline', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-08-30T10:00:00.000Z'));
    installBrowserGlobals();
    const putEvent = vi.fn<InteractionOutbox['putEvent']>(async () => ({
      stored: true,
      dropped: {}
    }));
    const outbox: InteractionOutbox = {
      putSession: vi.fn(async () => undefined),
      markStopped: vi.fn(async () => undefined),
      putEvent,
      sessions: vi.fn(async () => []),
      events: vi.fn(async () => []),
      acknowledge: vi.fn(async () => undefined),
      abandon: vi.fn(async () => undefined)
    };
    const recorder = new ProjectInteractionRecorder({
      projectId: 'project-one',
      capture: mainStudyV1.interactionCapture!,
      captureEndsAt: '2026-08-30T10:00:01.000Z',
      applicationVersion: 'test',
      outbox,
      fetch: vi.fn(async () => new Response(null, { status: 503 }))
    });
    recorder.start(new EventTarget() as HTMLElement);
    recorder.recordWorkspaceState(workspaceObservation());
    await recorder.flush();

    vi.advanceTimersByTime(1_001);
    recorder.recordWorkspaceState({ ...workspaceObservation(), projectHead: 2 });
    recorder.recordDraft([{ type: 'markdown', text: 'too late' }], true);
    await recorder.flush();

    expect(putEvent).toHaveBeenCalledTimes(1);
    expect(putEvent.mock.calls[0]?.[0].event.kind).toBe('workspace.state');
  });
});

function installBrowserGlobals(): void {
  vi.stubGlobal(
    'document',
    Object.assign(new EventTarget(), { visibilityState: 'visible', hasFocus: () => true })
  );
  vi.stubGlobal('window', new EventTarget());
  vi.stubGlobal('innerWidth', 1280);
  vi.stubGlobal('innerHeight', 720);
  vi.stubGlobal('devicePixelRatio', 1);
}

function workspaceObservation() {
  return {
    projectHead: 1,
    connection: 'open' as const,
    atHead: true,
    layout: 'single' as const,
    visiblePresentationIds: [],
    followingLatestPresentations: true,
    focusedTimelineEvents: [],
    visualSelections: [],
    viewports: [],
    draft: { hasContent: false, characterCount: 0, referenceCount: 0, focused: false },
    document: {
      visibility: 'visible' as const,
      focused: true,
      viewport: { width: 1280, height: 720, devicePixelRatio: 1 }
    }
  };
}
