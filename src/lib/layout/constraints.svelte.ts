// import { type Variable, type Interval, p } from './layout.svelte';
import * as penrose from '@penrose/core';
import type { NodeBounds } from './node.svelte';

export type ConstraintFunc<Args extends penrose.Num[] = penrose.Num[]> = (
  ...args: Args
) => penrose.Num;

export const eq: ConstraintFunc<[penrose.Num, penrose.Num]> = (a, b) => {
  return penrose.log2(penrose.absVal(penrose.sub(a, b)));
};

export const between: ConstraintFunc<[penrose.Num, penrose.Num, penrose.Num]> = (
  value,
  min,
  max
) => {
  return penrose.add(penrose.lessThan(min, value), penrose.lessThan(value, max));
};

export const minimize: ConstraintFunc<[penrose.Num]> = (value) => {
  return penrose.log2(penrose.absVal(value));
};

export const lessThan: ConstraintFunc<[penrose.Num, penrose.Num, number]> = (a, b, padding = 0) => {
  const gap = penrose.add(penrose.sub(a, b), padding);
  const violation = penrose.max(gap, 0);
  const penalty = penrose.pow(violation, 2);
  return penalty;
};

export const add = penrose.add as ConstraintFunc;
export const sub = penrose.sub as ConstraintFunc;
export const mul = penrose.mul as ConstraintFunc;
export const div = penrose.div as ConstraintFunc;
export const absVal = penrose.absVal as ConstraintFunc;
export const log2 = penrose.log2 as ConstraintFunc;
export const max = penrose.max as ConstraintFunc;
export const min = penrose.min as ConstraintFunc;

export const leftOf = (boundsA: NodeBounds, boundsB: NodeBounds, padding: number = 0) => {
  return lessThan(boundsA.right, boundsB.left, padding);
};

export const rightOf = (boundsA: NodeBounds, boundsB: NodeBounds, padding: number = 0) => {
  return lessThan(boundsA.left, boundsB.right, padding);
};

// export const rowAlign = (bounds: NodeBounds[], padding: number = 0) => {
//   const constraints: penrose.Num[] = [];
//   for (let i = 0; i < bounds.length - 1; i++) {
//     constraints.push(lessThan(bounds[i].right, bounds[i + 1].left, padding));
//   }
//   return penrose.add(...constraints);
// };

// const eq = (a: p.Num, b: p.Num): p.Num => {
//   return p.log2(p.absVal(p.sub(a, b)));
// }

//   const constraint = {
//     eq: layout.defineConstraint('eq', (a: Temporal<Variable>, b: Temporal<Variable>) => {
//       return [p.log2(p.absVal(p.sub(a.at(layout.time), b.at(layout.time))))];
//     }),

//     between: layout.defineConstraint('between', (value: Temporal<Variable>, range: Interval) => {
//       const { min, max } = range;
//       return [p.lessThan(min, value.at(layout.time)), p.lessThan(value.at(layout.time), max)];
//     }),

//     assign: layout.defineConstraint('assign', (nodeA: Node, nodeB: Node) => {
//       const { left: aLeft, top: aTop, right: aRight, bottom: aBottom } = nodeA.bounds(layout.time);
//       const { left: bLeft, top: bTop, right: bRight, bottom: bBottom } = nodeB.bounds(layout.time);
//       return [
//         p.mul(p.absVal(p.sub(aLeft, bLeft)), 1),
//         p.mul(p.absVal(p.sub(aTop, bTop)), 1),
//         p.mul(p.absVal(p.sub(aRight, bRight)), 1),
//         p.mul(p.absVal(p.sub(aBottom, bBottom)), 1)
//       ];
//     }),

//     minimize: layout.defineConstraint('minimize', (value: Temporal<Variable>) => {
//       return [p.log2(p.absVal(value.at(layout.time)))];
//     }),

//     contains: layout.defineConstraint('contains', (containerNode: Node, node: Node) => {
//       const { left: cLeft, top: cTop, right: cRight, bottom: cBottom } = containerNode.bounds();
//       const { left, top, right, bottom } = node.bounds();

//       return [
//         p.lessThan(cLeft, left, 0),
//         p.lessThan(right, cRight, 0),
//         p.lessThan(cTop, top, 0),
//         p.lessThan(bottom, cBottom, 0)
//       ];
//     }),

//     disjoint: layout.defineConstraint('disjoint', (nodeA: Node, nodeB: Node) => {
//       const {
//         left: aLeft,
//         top: aTop,
//         right: aRight,
//         bottom: aBottom,
//         width: aWidth,
//         height: aHeight
//       } = nodeA.bounds(layout.time);
//       const {
//         left: bLeft,
//         top: bTop,
//         right: bRight,
//         bottom: bBottom,
//         width: bWidth,
//         height: bHeight
//       } = nodeB.bounds(layout.time);

//       const overlapX = p.max(0, p.sub(p.min(aRight, bRight), p.max(aLeft, bLeft)));
//       const overlapY = p.max(0, p.sub(p.min(aBottom, bBottom), p.max(aTop, bTop)));

//       const normOverlapX = p.div(overlapX, p.max(1, p.min(aWidth, bWidth)));
//       const normOverlapY = p.div(overlapY, p.max(1, p.min(aHeight, bHeight)));

//       const overlapFraction = p.mul(100, p.mul(normOverlapX, normOverlapY));

//       return [overlapFraction];
//     }),

//     adjacentX: layout.defineConstraint(
//       'adjacentX',
//       (nodeA: Node, nodeB: Node, padding: number = 0) => {
//         const { right: aRight } = nodeA.bounds(layout.time);
//         const { left: bLeft } = nodeB.bounds(layout.time);

//         return [p.lessThanWithPadding(aRight, bLeft, padding)];
//       }
//     ),

//     adjacentY: layout.defineConstraint(
//       'adjacentY',
//       (nodeA: Node, nodeB: Node, padding: number = 0) => {
//         const { bottom: aBottom } = nodeA.bounds(layout.time);
//         const { top: bTop } = nodeB.bounds(layout.time);

//         return [p.lessThanWithPadding(aBottom, bTop, padding)];
//       }
//     ),

//     above: layout.defineConstraint('above', (nodeA: Node, nodeB: Node, padding: number = 0) => {
//       const { bottom: aBottom } = nodeA.bounds(layout.time);
//       const { top: bTop } = nodeB.bounds(layout.time);

//       return [p.lessThanWithPadding(aBottom, bTop, padding)];
//     }),

//     centerX: layout.defineConstraint('centerX', (containerNode: Node, node: Node) => {
//       const { left: nLeft, right: nRight } = node.bounds(layout.time);
//       const { left: cLeft, right: cRight } = containerNode.bounds(layout.time);

//       const distToLeft = p.sub(nLeft, cLeft);
//       const distToRight = p.sub(cRight, nRight);
//       const imbalance = p.absVal(p.sub(distToLeft, distToRight));

//       return [p.log2(imbalance)];
//     })
//   };
