import { LayoutCSP, type Variable, type Interval, p } from './layout.svelte';
import { type Temporal } from './temporal';
import { type NodeView, Node, type NodeConfig } from './node.svelte';

type LayoutConfig = {
  width?: number;
  height?: number;
  unitSize?: number;
};

export function createLayout(config: LayoutConfig = {}) {
  const { width: rootWidth, height: rootHeight, unitSize = 1 } = config;

  const layout = new LayoutCSP(unitSize);

  const root = new Node(layout, {
    style: {
      width: rootWidth ?? 1200,
      height: rootHeight ?? 800,
      left: 0,
      top: 0
    }
  });

  const constraint = {
    eq: layout.defineConstraint('eq', (a: Temporal<Variable>, b: Temporal<Variable>) => {
      return [p.log2(p.absVal(p.sub(a.at(layout.time), b.at(layout.time))))];
    }),

    between: layout.defineConstraint('between', (value: Temporal<Variable>, range: Interval) => {
      const { min, max } = range;
      return [p.lessThan(min, value.at(layout.time)), p.lessThan(value.at(layout.time), max)];
    }),

    assign: layout.defineConstraint('assign', (nodeA: Node, nodeB: Node) => {
      const { left: aLeft, top: aTop, right: aRight, bottom: aBottom } = nodeA.bounds(layout.time);
      const { left: bLeft, top: bTop, right: bRight, bottom: bBottom } = nodeB.bounds(layout.time);
      return [
        p.mul(p.absVal(p.sub(aLeft, bLeft)), 1),
        p.mul(p.absVal(p.sub(aTop, bTop)), 1),
        p.mul(p.absVal(p.sub(aRight, bRight)), 1),
        p.mul(p.absVal(p.sub(aBottom, bBottom)), 1)
      ];
    }),

    minimize: layout.defineConstraint('minimize', (value: Temporal<Variable>) => {
      return [p.log2(p.absVal(value.at(layout.time)))];
    }),

    contains: layout.defineConstraint('contains', (containerNode: Node, node: Node) => {
      const { left: cLeft, top: cTop, right: cRight, bottom: cBottom } = containerNode.bounds();
      const { left, top, right, bottom } = node.bounds();

      return [
        p.lessThanWithPadding(cLeft, left, 0),
        p.lessThanWithPadding(right, cRight, 0),
        p.lessThanWithPadding(cTop, top, 0),
        p.lessThanWithPadding(bottom, cBottom, 0)
      ];
    }),

    disjoint: layout.defineConstraint('disjoint', (nodeA: Node, nodeB: Node) => {
      const {
        left: aLeft,
        top: aTop,
        right: aRight,
        bottom: aBottom,
        width: aWidth,
        height: aHeight
      } = nodeA.bounds(layout.time);
      const {
        left: bLeft,
        top: bTop,
        right: bRight,
        bottom: bBottom,
        width: bWidth,
        height: bHeight
      } = nodeB.bounds(layout.time);

      const overlapX = p.max(0, p.sub(p.min(aRight, bRight), p.max(aLeft, bLeft)));
      const overlapY = p.max(0, p.sub(p.min(aBottom, bBottom), p.max(aTop, bTop)));

      const normOverlapX = p.div(overlapX, p.max(1, p.min(aWidth, bWidth)));
      const normOverlapY = p.div(overlapY, p.max(1, p.min(aHeight, bHeight)));

      const overlapFraction = p.mul(100, p.mul(normOverlapX, normOverlapY));

      return [overlapFraction];
    }),

    adjacentX: layout.defineConstraint(
      'adjacentX',
      (nodeA: Node, nodeB: Node, padding: number = 0) => {
        const { right: aRight } = nodeA.bounds(layout.time);
        const { left: bLeft } = nodeB.bounds(layout.time);

        return [p.lessThanWithPadding(aRight, bLeft, padding)];
      }
    ),

    adjacentY: layout.defineConstraint(
      'adjacentY',
      (nodeA: Node, nodeB: Node, padding: number = 0) => {
        const { bottom: aBottom } = nodeA.bounds(layout.time);
        const { top: bTop } = nodeB.bounds(layout.time);

        return [p.lessThanWithPadding(aBottom, bTop, padding)];
      }
    ),

    above: layout.defineConstraint('above', (nodeA: Node, nodeB: Node, padding: number = 0) => {
      const { bottom: aBottom } = nodeA.bounds(layout.time);
      const { top: bTop } = nodeB.bounds(layout.time);

      return [p.lessThanWithPadding(aBottom, bTop, padding)];
    }),

    centerX: layout.defineConstraint('centerX', (containerNode: Node, node: Node) => {
      const { left: nLeft, right: nRight } = node.bounds(layout.time);
      const { left: cLeft, right: cRight } = containerNode.bounds(layout.time);

      const distToLeft = p.sub(nLeft, cLeft);
      const distToRight = p.sub(cRight, nRight);
      const imbalance = p.absVal(p.sub(distToLeft, distToRight));

      return [p.log2(imbalance)];
    })
  };

  return {
    get ready(): boolean {
      return !layout.isDirty;
    },

    get views(): NodeView[][] {
      return layout.views;
    },

    get constraint() {
      return constraint;
    },

    get createNode() {
      return (style?: NodeConfig['style']) => {
        return new Node(layout, { style: style ?? {} });
      };
    },

    get root() {
      return root;
    },

    get timeSteps() {
      return layout.time;
    },

    step: layout.step.bind(layout),
    get global() {
      return {
        varying: (id?: string) => layout.varying('global', id),
        uniform: (id?: string) => layout.uniform('global', id)
      };
    },
    solve: layout.solve.bind(layout)
  };
}
