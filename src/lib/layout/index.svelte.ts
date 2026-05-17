import * as p from '@penrose/core';

type Interval = {
  min: number;
  max: number;
};

type VariableInfo = {
  v: p.Var;
  range: Interval;
};

type Scope = {
  [key: string]: VariableInfo;
};

export type NodeConfig = {
  style: Record<string, string | number>;
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
  parent?: Node;
  children: Node[];
  style: Record<string, StyleValue>;
  locals: Scope;
  addNode: (style?: Record<string, '?' | string | number>) => Node;
};

export type NodeView = {
  nodeId: string;
  style: Record<string, string>;
};

const parseVariableName = (name: string): string => {
  if (!name) {
    throw new Error(`Variable name cannot be empty`);
  }
  // ensure all lowercase and underscores only
  if (!/^[a-z_][a-z0-9_]*$/.test(name)) {
    throw new Error(`Invalid variable name: ${name}`);
  }
  return name;
};

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
  width?: number;
  height?: number;
};

export function createLayout(config: LayoutConfig = {}) {
  const { width: rootWidth, height: rootHeight } = config;

  const nodes = {} as Record<string, Node>;
  const variables = [] as VariableInfo[];
  const globals = {} as Scope;
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

  const boundingBox = (node: Node) => {
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
    contains: (containerNode: Node, node: Node) => {
      const { left: cLeft, top: cTop, right: cRight, bottom: cBottom } = boundingBox(containerNode);
      const { left, top, right, bottom } = boundingBox(node);

      addConstraints([p.lessThan(cLeft, left), p.lessThan(right, cRight)]);
      addConstraints([p.lessThan(cTop, top), p.lessThan(bottom, cBottom)]);
    },

    // Ensure nodes A and B do not overlap
    disjoint: (nodeA: Node, nodeB: Node) => {
      const { left: aLeft, top: aTop, right: aRight, bottom: aBottom } = boundingBox(nodeA);
      const { left: bLeft, top: bTop, right: bRight, bottom: bBottom } = boundingBox(nodeB);

      const overlapX = p.max(0, p.sub(p.min(aRight, bRight), p.max(aLeft, bLeft)));
      const overlapY = p.max(0, p.sub(p.min(aBottom, bBottom), p.max(aTop, bTop)));

      const normOverlapX = p.div(overlapX, 100);
      const normOverlapY = p.div(overlapY, 100);

      const overlapFraction = p.mul(normOverlapX, normOverlapY);

      addConstraints([p.absVal(overlapFraction)]);
    }
  };

  const variable = (scope: Scope, name: string): p.Var => {
    // Check if variable already exists in the current scope
    if (name in scope) {
      return scope[name].v;
    }

    // Create new variable in the current scope
    console.log(`Creating variable ${name}`);
    const varRange: Interval = { min: 1, max: 1000 };
    const varInfo = { v: p.variable(0), range: varRange };

    addConstraints([
      p.lessThan(varInfo.range.min, varInfo.v),
      p.lessThan(varInfo.v, varInfo.range.max)
    ]);

    scope[name] = varInfo;
    variables.push(varInfo);

    return varInfo.v;
  };

  const addNode = (
    config: NodeConfig = { style: {} },
    parent: Node | null,
    scope: Scope = globals
  ) => {
    if (config.style.x !== undefined) {
      config.style.left = config.style.x;
      delete config.style.x;
    }

    if (config.style.y !== undefined) {
      config.style.top = config.style.y;
      delete config.style.y;
    }

    config = {
      style: {
        width: `?`,
        height: `?`,
        left: `?`,
        top: `?`,
        ...config.style
      }
    };

    const siblingCount = parent ? parent.children.length : Object.keys(nodes).length;

    const node: Node = {
      id: parent ? `${parent.id}-${siblingCount + 1}` : `root`,
      parent: parent || undefined,
      children: [],
      style: {},
      locals: {},
      addNode: (style?: Record<string, string | number>) => addNode({ style: style ?? {} }, node)
    };

    for (const [key, value] of Object.entries(config.style)) {
      if (typeof value === 'string' && value[0] === '?') {
        // Implicit variable (default)
        const varName = parseVariableName(key);
        node.style[key] = {
          type: 'variable',
          value: variable(node.locals, varName)
        };
      } else if (typeof value === 'string' && value[0] === '$') {
        // Explicit variable (e.g. "$width" -> variable named "width")
        const varName = parseVariableName(value.slice(1));
        node.style[key] = {
          type: 'variable',
          value: variable(scope, varName)
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

    nodes[node.id] = node;

    if (parent) {
      // Ensure child is tracked in parent's children list for traversal
      parent.children.push(node);

      // Child element must be fully contained within parent
      constraint.contains(parent, node);
    }

    return node;
  };

  const root = addNode(
    {
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
    console.log('Global variables:', globals);

    // Randomize initial variable values to help solver escape local minima
    for (const { v, range } of variables) {
      const randomValue = Math.random() * (range.max - range.min) + range.min;
      v.val = randomValue;
    }

    const problem = await p.problem({
      constraints: [...constraints]
    });

    const result = problem.start({}).run({});
    console.log('Solver result:', result);

    output.views = Object.values(nodes).map((node) => {
      const style: Record<string, string> = {};
      for (const [key, value] of Object.entries(node.style)) {
        if (value.type === 'variable') {
          // console.log(
          //   `Getting value for variable ${key} of node ${node.id}:`,
          //   result.vals.get(value.value)
          // );
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
      return (style?: Record<string, '?' | string | number>) =>
        addNode({ style: style ?? {} }, root);
    },

    get root() {
      return root;
    },
    addVariable: variable,
    solve
  };
}
