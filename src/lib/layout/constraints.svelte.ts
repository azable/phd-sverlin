// import { type Variable, type Interval, p } from './layout.svelte';
import * as penrose from '@penrose/core';

export const eq = (a: penrose.Num, b: penrose.Num): penrose.Num => {
  return penrose.log2(penrose.absVal(penrose.sub(a, b)));
};

export const between = (value: penrose.Num, min: penrose.Num, max: penrose.Num): penrose.Num => {
  return penrose.add(penrose.lessThan(min, value), penrose.lessThan(value, max));
};

export const minimize = (value: penrose.Num): penrose.Num => {
  return penrose.log2(penrose.absVal(value));
};

export const lessThan = (a: penrose.Num, b: penrose.Num, padding: penrose.Num = 0): penrose.Num => {
  const gap = penrose.add(penrose.sub(a, b), padding);
  const violation = penrose.max(gap, 0);
  const penalty = penrose.pow(violation, 2);
  return penalty;
};

export const add = penrose.add;
export const sub = penrose.sub;
export const mul = penrose.mul;
export const div = penrose.div;
export const absVal = penrose.absVal;
export const log2 = penrose.log2;
export const max = penrose.max;
export const min = penrose.min;

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
