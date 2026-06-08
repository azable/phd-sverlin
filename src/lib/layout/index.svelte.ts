import { LayoutCSP } from './layout.svelte';
import { type NodeView } from './node.svelte';
import * as penrose from '@penrose/core';

type LayoutConfig = {
  width?: number;
  height?: number;
  unitSize?: number;
};

export async function createLayout(config: LayoutConfig = {}) {
  const { width: rootWidth, height: rootHeight, unitSize = 1 } = config;

  const layout = await LayoutCSP.create(rootWidth ?? 1200, rootHeight ?? 800, unitSize);

  return {
    get ready(): boolean {
      return !layout.isDirty;
    },

    get views(): NodeView[][] {
      return layout.views;
    },

    get constraint() {
      return (expr: penrose.Num) => layout.constraint('global').set(expr);
    },

    get variable() {
      return (id?: string) => layout.variable('global', id);
    },

    get timeSteps() {
      return layout.time;
    },

    step: layout.step.bind(layout),
    solve: layout.solve.bind(layout)
  };
}
