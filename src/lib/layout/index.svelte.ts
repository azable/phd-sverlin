import * as p from '@penrose/core';

export type NodeConfig = {
  id: string;
  style: Record<string, '?' | string | number>;
};

type StyleValue =
  | {
      type: 'variable';
      value: p.Var;
    }
  | {
      type: 'constant';
      value: number;
    }
  | {
      type: 'fixed';
      value: string;
    };

type Node = {
  id: string;
  style: Record<string, StyleValue>;
  addNode: (arg0: NodeConfig) => Node;
};

export type NodeView = {
  nodeId: string;
  style: Record<string, string>;
};

export const fixed = (value: string): StyleValue => ({
  type: 'fixed',
  value
});

const toCSSvalue = (key: string, value: number): string => {
  const map: Record<string, (value: number) => string> = {
    width: (v) => `${v}px`,
    height: (v) => `${v}px`,
    left: (v) => `${v}px`,
    top: (v) => `${v}px`,
    'font-size': (v) => `${v}px`
  };

  if (key in map) {
    return map[key](value);
  }
  throw new Error(`No CSS mapping for key: ${key}`);
};

type LayoutConfig = {
  rootWidth?: number;
  rootHeight?: number;
};

export function createLayout(config: LayoutConfig = {}) {
  const { rootWidth, rootHeight } = config;

  const nodes = {} as Record<string, Node>;
  const constraints = [] as p.Num[];
  const output = $state({
    views: [] as NodeView[]
  });

  const addConstraints = (newConstraints: p.Num[]) => {
    constraints.push(...newConstraints);
  };

  const num = (value: StyleValue): p.Num => {
    if (value.type === 'variable') {
      return value.value;
    } else if (value.type === 'constant') {
      return value.value;
    }
    throw new Error(`Cannot convert ${value.type} to number`);
  };

  const boundingBox = (nodeId: string) => {
    const node = nodes[nodeId];
    if (!node) {
      throw new Error(`Node not found: ${nodeId}`);
    }

    const left = num(node.style.left);
    const top = num(node.style.top);
    const width = num(node.style.width);
    const height = num(node.style.height);
    const right = p.add(left, width);
    const bottom = p.add(top, height);

    return { left, top, right, bottom, width, height };
  };

  const constraint = {
    // Ensure node A is fully contained within node B
    contains: (containerNodeId: string, nodeId: string) => {
      const {
        left: cLeft,
        top: cTop,
        right: cRight,
        bottom: cBottom
      } = boundingBox(containerNodeId);
      const { left, top, right, bottom } = boundingBox(nodeId);

      addConstraints([p.lessThan(cLeft, left), p.lessThan(right, cRight)]);
      addConstraints([p.lessThan(cTop, top), p.lessThan(bottom, cBottom)]);
    },

    // Ensure nodes A and B do not overlap
    disjoint: (nodeIdA: string, nodeIdB: string) => {
      const { left: aLeft, top: aTop, right: aRight, bottom: aBottom } = boundingBox(nodeIdA);
      const { left: bLeft, top: bTop, right: bRight, bottom: bBottom } = boundingBox(nodeIdB);

      const overlapX = p.max(0, p.sub(p.min(aRight, bRight), p.max(aLeft, bLeft)));
      const overlapY = p.max(0, p.sub(p.min(aBottom, bBottom), p.max(aTop, bTop)));

      const normOverlapX = p.div(overlapX, 100);
      const normOverlapY = p.div(overlapY, 100);

      const overlapFraction = p.mul(normOverlapX, normOverlapY);

      addConstraints([p.absVal(overlapFraction)]);
    }
  };

  const addVariable = (initial = Math.random() * 100): p.Var => {
    const v = p.variable(initial);
    addConstraints([p.sub(0, v)]);
    return v;
  };

  const addNode = (config: NodeConfig, parent: Node | null) => {
    config = {
      id: config.id,
      style: {
        width: '?',
        height: '?',
        left: '?',
        top: '?',
        ...config.style
      }
    };

    const node: Node = {
      id: config.id,
      style: {},
      addNode: (childConfig: NodeConfig) => addNode(childConfig, node)
    };

    for (const [key, value] of Object.entries(config.style)) {
      if (typeof value === 'string' && value[0] === '?') {
        console.log(`Creating variable for ${key} of node ${config.id}`);
        // Implicit variable creation
        node.style[key] = {
          type: 'variable',
          value: addVariable()
        };
      } else if (typeof value === 'number') {
        // A number/string is treated as a constant CSS attribute
        node.style[key] = {
          type: 'constant',
          value
        };
      } else if (typeof value === 'string') {
        node.style[key] = {
          type: 'fixed',
          value
        };
      }
    }

    nodes[config.id] = node;

    if (parent) {
      // Child element must be fully contained within parent
      constraint.contains(parent.id, node.id);
    }

    return node;
  };

  const root = addNode(
    {
      id: '_root',
      style: {
        width: rootWidth ?? '?',
        height: rootHeight ?? '?',
        left: 0,
        top: 0
      }
    },
    null
  );

  const solve = async () => {
    console.log('Solving layout with constraints:', constraints);

    const problem = await p.problem({
      constraints: [...constraints]
    });

    const result = problem.start({}).run({});
    console.log('Solver result:', result);

    output.views = Object.values(nodes).map((node) => {
      const style: Record<string, string> = {};
      for (const [key, value] of Object.entries(node.style)) {
        if (value.type === 'variable') {
          console.log(
            `Getting value for variable ${key} of node ${node.id}:`,
            result.vals.get(value.value)
          );
          style[key] = toCSSvalue(key, result.vals.get(value.value) as number);
        } else if (value.type === 'constant') {
          style[key] = toCSSvalue(key, value.value);
        } else if (value.type === 'fixed') {
          style[key] = value.value;
        }
      }
      return { nodeId: node.id, style };
    });
  };

  return {
    get views(): NodeView[] {
      return output.views;
    },

    get constraint() {
      return constraint;
    },

    get addNode() {
      return (id: string, style: Record<string, '?' | string | number>) =>
        addNode({ id, style }, root);
    },

    get root() {
      return root;
    },
    addVariable,
    solve
  };
}
