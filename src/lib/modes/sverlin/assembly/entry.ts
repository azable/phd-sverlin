// Fixed browser entry for every presentation: mount the authored component with the step and seed
// that the sandbox document injects for the selected playback position.

import { mount } from 'svelte';
import Main from 'virtual:component';

const playback = window as typeof window & { __sverlinStep?: number; __sverlinSeed?: number };

mount(Main, {
  target: document.getElementById('app') ?? document.body,
  props: { step: playback.__sverlinStep ?? 0, seed: playback.__sverlinSeed ?? 1 }
});
