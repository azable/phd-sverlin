// Fixed browser entry for every presentation: mount the authored component inside the page frame,
// with the state recorded for a step, plus the step and seed. The sandbox document injects the
// first step; later steps arrive as messages from the app and are shown without reloading the page.
// Nodes find the atomic types of their values, and each type's parent and unit, through the
// 'sverlin:types' context.

import { mount, unmount, type Component } from 'svelte';
import { Frame, themeCss, type FrameSettings, type LayoutMemory } from 'sverlin';
import Main from 'virtual:component';
import atoms from 'virtual:atoms';
import states from 'virtual:trace';

// The page theme every node draws on: colour tokens, the canvas, and spacing for the page itself.
const theme = document.createElement('style');
theme.textContent = `${themeCss}
.sv-layer { position: fixed; inset: 0; }
.sv-layer.pending { visibility: hidden; }`;
document.head.append(theme);

type StepState = Record<string, unknown> & {
  __types?: Record<string, string>;
  __defaults?: { font?: string } & Record<string, unknown>;
  __frame: FrameSettings;
};

const playback = window as typeof window & {
  __sverlinStep?: number;
  __sverlinSeed?: number;
  __sverlinSelection?: unknown;
};
const clampStep = (step: number) => Math.min(Math.max(step, 0), states.length - 1);

// The drawn font applies page-wide, so every node inherits it unless it sets its own. Drawn
// defaults belong to the presentation, so every step shares them.
const fonts: Record<string, string> = {
  sans: 'system-ui, sans-serif',
  serif: "ui-serif, Georgia, 'Times New Roman', serif",
  mono: "ui-monospace, 'SFMono-Regular', Menlo, Consolas, monospace"
};
const font = (states[0] as StepState).__defaults?.font;
if (font && fonts[font]) document.documentElement.style.fontFamily = fonts[font];

/** A type's unit, or that of the nearest type it refines. */
function unitOf(typeName: string): string | undefined {
  for (let name: string | undefined = typeName; name && atoms[name]; name = atoms[name].parent)
    if (atoms[name].unit) return atoms[name].unit;
  return undefined;
}

type Shown = { step: number; layer: HTMLElement; app: Record<string, unknown> };
const root = document.getElementById('app') ?? document.body;
let current: Shown | undefined;
let pending: Shown | undefined;

// Layouts for every step, made once in step order before any step is shown (see LayoutMemory).
const scopes: LayoutMemory['scopes'] = new Map();
const fits: LayoutMemory['fits'] = new Map();
const reserved: LayoutMemory['reserved'] = new Map();

/** Measuring finds each node's natural sizes, recording makes the layouts, showing replays them. */
type Phase = 'measuring' | 'recording' | 'showing';

/** Mount a step's frame in a hidden layer; `settled` runs once its layout stops changing. */
function mountStep(step: number, phase: Phase, settled: (shown: Shown) => void): Shown {
  const {
    __types: types = {},
    __defaults: defaults,
    __frame: frame,
    ...state
  } = states[step] as StepState;
  // Arrays and objects in the props, by path, so a node can find the types of its items.
  const paths = new WeakMap<object, string>();
  const record = (value: unknown, path: string): void => {
    if (value === null || typeof value !== 'object') return;
    paths.set(value, path);
    if (Array.isArray(value)) value.forEach((item, index) => record(item, `${path}[${index}]`));
    else for (const [key, item] of Object.entries(value)) record(item, `${path}.${key}`);
  };
  for (const [name, value] of Object.entries(state)) record(value, name);

  const layer = document.createElement('div');
  layer.className = 'sv-layer pending';
  root.append(layer);
  const shown: Shown = { step, layer, app: {} };
  const memory: LayoutMemory = {
    step,
    recording: phase === 'recording',
    measuring: phase === 'measuring',
    scopes,
    fits,
    reserved
  };
  shown.app = mount(Frame, {
    target: layer,
    props: {
      view: Main as Component<Record<string, unknown>>,
      props: { ...state, step, seed: playback.__sverlinSeed ?? 1 },
      settings: frame,
      onsettled: () => settled(shown)
    },
    context: new Map<string, unknown>([
      ['sverlin:defaults', defaults],
      ['sverlin:layout-memory', memory],
      [
        'sverlin:types',
        {
          itemType: (container: unknown, index: number) => {
            const path =
              container !== null && typeof container === 'object'
                ? paths.get(container)
                : undefined;
            return path === undefined ? undefined : types[`${path}[${index}]`];
          },
          parent: (typeName: string) => atoms[typeName]?.parent,
          unit: unitOf
        }
      ]
    ])
  });
  return shown;
}

function remove(shown: Shown) {
  unmount(shown.app);
  shown.layer.remove();
}

/**
 * Show a step from the records: mount it in a hidden layer, and once its layout settles, reveal it
 * and remove the step it replaces, so neither a blank page nor an unfinished layout is ever visible.
 */
function show(step: number) {
  if (pending) remove(pending);
  pending = mountStep(step, 'showing', (shown) => {
    if (pending !== shown) return;
    shown.layer.classList.remove('pending');
    if (current) remove(current);
    current = shown;
    pending = undefined;
  });
}

/**
 * Measure every node at every step, keeping the largest size each reaches, then lay out every step
 * in order, each from the one before, recording what each step shows.
 */
async function recordSteps() {
  // A page loaded while hidden has no layout to measure until it is shown.
  while (!document.documentElement.clientWidth)
    await new Promise((resume) => addEventListener('resize', resume, { once: true }));
  const pass = (step: number, phase: Phase, finish: (shown: Shown) => void) =>
    new Promise<void>((done) =>
      mountStep(step, phase, (shown) => {
        finish(shown);
        remove(shown);
        done();
      })
    );
  for (let step = 0; step < states.length; step++)
    await pass(step, 'measuring', ({ layer }) => {
      for (const node of layer.querySelectorAll<HTMLElement>('[data-sv-node]')) {
        const id = node.dataset.svNode as string;
        const largest = reserved.get(id);
        // Layout sizes, unaffected by the frame's scale or the root's fit.
        const width = node.offsetWidth;
        const height = node.offsetHeight;
        reserved.set(id, {
          width: Math.max(largest?.width ?? 0, width),
          height: Math.max(largest?.height ?? 0, height)
        });
      }
    });
  for (let step = 0; step < states.length; step++) await pass(step, 'recording', () => {});
}

let requested = clampStep(playback.__sverlinStep ?? 0);
let recorded = false;

// The app sends each new step, with the selection to show in it; the page and its layout engine
// stay loaded, and the canvas view carries over.
addEventListener('message', (event: MessageEvent) => {
  if (event.source !== window.parent) return;
  const data = event.data as { type?: unknown; step?: unknown; selection?: unknown };
  if (data?.type !== 'sverlin:step' || typeof data.step !== 'number') return;
  const step = clampStep(data.step);
  playback.__sverlinSelection = Array.isArray(data.selection) ? data.selection : [];
  requested = step;
  if (recorded && step !== (pending ?? current)?.step) show(step);
});

if (window.parent !== window) window.parent.postMessage({ type: 'sverlin:loaded' }, '*');
void recordSteps().then(() => {
  recorded = true;
  show(requested);
});
