// Fixed browser entry for every presentation: mount the authored component with the state recorded
// for the selected step, plus the step and seed that the sandbox document injects.

import { mount } from 'svelte';
import Main from 'virtual:component';
import states from 'virtual:trace';

const playback = window as typeof window & { __sverlinStep?: number; __sverlinSeed?: number };
const step = Math.min(Math.max(playback.__sverlinStep ?? 0, 0), states.length - 1);

mount(Main, {
  target: document.getElementById('app') ?? document.body,
  props: { ...states[step], step, seed: playback.__sverlinSeed ?? 1 }
});
