import { variable, problem as makeProblem, type Var } from '@penrose/core';

export type NodeConfig = {
  id: string;
  style: Record<string, '?' | string | number>;
};

type StyleValue =
  | {
      type: 'variable';
      value: Var;
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
};

export type NodeView = {
  nodeId: string;
  style: Record<string, string>;
};

const defaultNodeStyle: Record<string, '?' | string | number> = {
  width: '?',
  height: '?',
  left: '?',
  top: '?'
};

const toCSSvalue = (key: string, value: number): string => {
  const map: Record<string, (value: number) => string> = {
    width: (v) => `${v}px`,
    height: (v) => `${v}px`,
    left: (v) => `${v}px`,
    top: (v) => `${v}px`
  };

  if (key in map) {
    return map[key](value);
  }
  throw new Error(`No mapping for CSS property: ${key}`);
};

export function createLayout(initialNodes: NodeConfig[] = []) {
  const nodes = $state({} as Record<string, Node>);

  const addVariable = (initial = 0): Var => {
    return variable(initial);
  };

  const addNode = (config: NodeConfig) => {
    config = {
      id: config.id,
      style: {
        ...defaultNodeStyle,
        ...config.style
      }
    };

    const node: Node = {
      id: config.id,
      style: {}
    };

    for (const [key, value] of Object.entries(node.style)) {
      if (typeof value === 'string' && value === '?') {
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

    return node;
  };

  initialNodes.forEach(addNode);

  const output = $state({
    views: [] as NodeView[]
  });

  const solve = async () => {
    const opt = makeProblem({
      constraints: [] // TODO: add constraints here
    });

    const result = (await opt).start({}).run({});

    console.log('Solver result:', result);

    output.views = Object.values(nodes).map((node) => {
      const style: Record<string, string> = {};
      for (const [key, value] of Object.entries(node.style)) {
        if (value.type === 'variable') {
          style[key] = toCSSvalue(key, value.value.val);
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
      return {};
    },

    addNode,
    addVariable,
    solve
  };
}
