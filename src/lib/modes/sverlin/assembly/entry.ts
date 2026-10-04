// Fixed browser entry for every presentation: mount the authored component with the state recorded
// for the selected step, plus the step and seed that the sandbox document injects. Nodes find the
// atomic types of their values, and each type's parent and unit, through the 'sverlin:types' context.

import { mount } from 'svelte';
import { themeCss } from 'sverlin';
import Main from 'virtual:component';
import atoms from 'virtual:atoms';
import states from 'virtual:trace';

// The page theme every node draws on: colour tokens, the canvas, and spacing for the page itself.
const theme = document.createElement('style');
theme.textContent = themeCss;
document.head.append(theme);

const playback = window as typeof window & { __sverlinStep?: number; __sverlinSeed?: number };
const step = Math.min(Math.max(playback.__sverlinStep ?? 0, 0), states.length - 1);
const { __types: types = {}, ...state } = states[step] as Record<string, unknown> & {
  __types?: Record<string, string>;
};

// Arrays and objects in the props, by path, so a node can find the types of its items.
const paths = new WeakMap<object, string>();
const record = (value: unknown, path: string): void => {
  if (value === null || typeof value !== 'object') return;
  paths.set(value, path);
  if (Array.isArray(value)) value.forEach((item, index) => record(item, `${path}[${index}]`));
  else for (const [key, item] of Object.entries(value)) record(item, `${path}.${key}`);
};
for (const [name, value] of Object.entries(state)) record(value, name);

/** A type's unit, or that of the nearest type it refines. */
function unitOf(typeName: string): string | undefined {
  for (let name: string | undefined = typeName; name && atoms[name]; name = atoms[name].parent)
    if (atoms[name].unit) return atoms[name].unit;
  return undefined;
}

mount(Main, {
  target: document.getElementById('app') ?? document.body,
  props: { ...state, step, seed: playback.__sverlinSeed ?? 1 },
  context: new Map([
    [
      'sverlin:types',
      {
        itemType: (container: unknown, index: number) => {
          const path =
            container !== null && typeof container === 'object' ? paths.get(container) : undefined;
          return path === undefined ? undefined : types[`${path}[${index}]`];
        },
        parent: (typeName: string) => atoms[typeName]?.parent,
        unit: unitOf
      }
    ]
  ])
});
