import { Position, type XYPosition, type InternalNode } from '@xyflow/svelte';

// this helper function returns the intersection point
// of the line between the center of the intersectionNode and the target node
// Returns the intersection point of the line from intersectionNode's center
// to targetNode's center with the boundary of intersectionNode treated as a circle.
function getNodeIntersection(intersectionNode: InternalNode, targetNode: InternalNode) {
  const intersectionPos = intersectionNode.internals.positionAbsolute ?? { x: 0, y: 0 };
  const targetPos = targetNode.internals.positionAbsolute ?? { x: 0, y: 0 };

  const iw = intersectionNode.measured.width ?? 0;
  const ih = intersectionNode.measured.height ?? 0;
  const tw = targetNode.measured.width ?? 0;
  const th = targetNode.measured.height ?? 0;

  // centers
  const cx = intersectionPos.x + iw / 2;
  const cy = intersectionPos.y + ih / 2;
  const tx = targetPos.x + tw / 2;
  const ty = targetPos.y + th / 2;

  // direction from intersection center -> target center
  const dx = tx - cx;
  const dy = ty - cy;

  // circle radius (inscribed in node's box)
  const r = Math.min(iw, ih) / 2;

  // handle degenerate case (same center or zero size)
  const len = Math.hypot(dx, dy);
  if (len === 0 || r === 0) {
    return { x: cx, y: cy };
  }

  // normalize and step out to circle boundary
  const ux = dx / len;
  const uy = dy / len;

  return { x: cx + ux * r, y: cy + uy * r };
}

// returns the position (top,right,bottom or right) passed node compared to the intersection point
function getEdgePosition(node: InternalNode, intersectionPoint: XYPosition) {
  if (!node.measured.width || !node.measured.height) {
    return null;
  }
  const nx = Math.round(node.internals.positionAbsolute?.x ?? 0);
  const ny = Math.round(node.internals.positionAbsolute?.y ?? 0);
  const px = Math.round(intersectionPoint.x);
  const py = Math.round(intersectionPoint.y);

  if (px <= nx + 1) {
    return Position.Left;
  }
  if (px >= nx + node.measured.width - 1) {
    return Position.Right;
  }
  if (py <= ny + 1) {
    return Position.Top;
  }
  if (py >= ny + node.measured.height - 1) {
    return Position.Bottom;
  }

  return Position.Top;
}

// returns the parameters (sx, sy, tx, ty, sourcePos, targetPos) you need to create an edge
export function getEdgeParams(source: InternalNode, target: InternalNode) {
  const sourceIntersectionPoint = getNodeIntersection(source, target);
  const targetIntersectionPoint = getNodeIntersection(target, source);

  const sourcePos = getEdgePosition(source, sourceIntersectionPoint);
  const targetPos = getEdgePosition(target, targetIntersectionPoint);

  return {
    sx: sourceIntersectionPoint.x,
    sy: sourceIntersectionPoint.y,
    tx: targetIntersectionPoint.x,
    ty: targetIntersectionPoint.y,
    sourcePos,
    targetPos
  };
}
