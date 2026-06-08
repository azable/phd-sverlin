import { LayoutCSP } from './layout.svelte';
import { type NodeView } from './node.svelte';
import * as penrose from '@penrose/core';
import { randomUUID } from './utils';

type LayoutConfig = {
  width?: number;
  height?: number;
  unitSize?: number;
};

export async function createLayout(config: LayoutConfig = {}) {
  const { width: rootWidth, height: rootHeight, unitSize = 1 } = config;

  const layout = await LayoutCSP.create(rootWidth ?? 1200, rootHeight ?? 800, unitSize);

  return {
    get views(): NodeView[][] {
      return layout.views;
    },

    get constraint() {
      return (expr: penrose.Num, id?: string) => {
        id ??= randomUUID();
        layout.constraint(id).set(expr);
      };
    },

    get variable() {
      return (id?: string) => {
        id ??= randomUUID();
        return layout.variable(id);
      };
    },

    get timeSteps() {
      return layout.time;
    },

    step: layout.step.bind(layout),
    solve: layout.solve.bind(layout)
  };
}
