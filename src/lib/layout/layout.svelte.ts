import * as penrose from '@penrose/core';
import * as _ from 'lodash-es';
import { type StyleValue, Node, type NodeView, type NodeConfig } from './node.svelte';
import { toCSSrule, toCSS } from './style';
import { randomUUID } from './utils';
import { tick } from 'svelte';
import { SvelteMap } from 'svelte/reactivity';

export type Interval = {
  min: number;
  max: number;
};

export class Variable implements penrose.Var {
  tag: 'Var';
  val: number;
  id: string;
  uuid: string;
  randomInit: Interval;

  constructor(id: string) {
    this.tag = 'Var';
    this.val = 0;
    this.id = id;
    this.uuid = randomUUID();
    this.randomInit = { min: 1, max: 1000 };
  }
}

export class Constraint {
  #id: string;
  #expr: penrose.Num;

  constructor(id: string) {
    this.#id = id;
    this.#expr = 0;
  }

  public get id() {
    return this.#id;
  }

  public get expr() {
    return this.#expr;
  }

  public set(expr: penrose.Num) {
    this.#expr = expr;
  }
}

export class LayoutCSP {
  #time: number = $state(-1);
  #unitSize: number;

  #root: Node | undefined;

  #nodes: SvelteMap<string, Node>[] = $state([new SvelteMap()]);
  #nodeIdCounter: number = 0;

  #variables: SvelteMap<string, Variable>;
  #constraints: SvelteMap<string, Constraint>;

  #views: NodeView[][] = $state([]);

  private constructor(unitSize: number = 1) {
    this.#unitSize = unitSize;
    this.#variables = new SvelteMap<string, Variable>();
    this.#constraints = new SvelteMap<string, Constraint>();
  }

  public static async create(
    canvasWidth: number,
    canvasHeight: number,
    unitSize: number = 1
  ): Promise<LayoutCSP> {
    const layout = new LayoutCSP(unitSize);
    const root = await Node.create(layout, 'root', {
      style: {
        width: canvasWidth,
        height: canvasHeight,
        left: 0,
        top: 0
      }
    });
    layout.#root = root;
    layout.#nodes[0].set(layout.#root.id, layout.#root);
    await tick();
    return layout;
  }

  private async node(config: NodeConfig, content?: string): Promise<string> {
    if (this.#root === undefined) {
      throw new Error('Root node not initialized');
    }
    const nodeId = `node-${this.#nodeIdCounter++}`;
    const node = await Node.create(this, nodeId, config, content);
    this.#nodes[this.time].set(node.id, node);
    node.within(this.#root);
    return node.id;
  }

  public async step(
    removeNodeIds: string[] = [],
    nodes: [NodeConfig['style'], string?][] = []
  ): Promise<string[]> {
    this.#time += 1;
    this.#nodes[this.time] =
      this.time > 0
        ? new SvelteMap(
            this.#nodes[this.time - 1]
              .entries()
              .filter(([nodeId]) => !removeNodeIds.includes(nodeId))
          )
        : new SvelteMap();

    return await Promise.all(
      nodes.map(async ([style, content]) => await this.node({ style }, content))
    );
  }

  public get time() {
    return this.#time;
  }

  public get unitSize() {
    return this.#unitSize;
  }

  private ensureUniqId(id: string | undefined): string {
    if (id === undefined || id === null) {
      return randomUUID();
    }
    return id;
  }

  public variable(namespace: string, id?: string): Variable {
    id = this.idWithNamespace(this.ensureUniqId(id), namespace);
    if (!this.#variables.has(id)) {
      this.#variables.set(id, new Variable(id));
    }
    return this.#variables.get(id)!;
  }

  public constraint(namespace: string, id?: string): Constraint {
    id = this.idWithNamespace(this.ensureUniqId(id), namespace);
    if (!this.#constraints.has(id)) {
      this.#constraints.set(id, new Constraint(id));
    }
    return this.#constraints.get(id)!;
  }

  public async solve() {
    const variables = this.#variables;
    const constraints = this.#constraints;

    // Randomize initial variable values to help solver escape local minima
    for (const v of variables.values()) {
      v.val = Math.random() * (v.randomInit.max - v.randomInit.min) + v.randomInit.min;
    }

    console.log('====================== SOLVE ======================');
    console.log(
      `>>> Variables (n=${variables.keys().toArray().length}):`,
      window.structuredClone(variables)
    );
    console.log(
      `>>> Constraints (n=${Object.keys(constraints).length}):`,
      window.structuredClone(constraints)
    );

    const solveIteration = async () => {
      const problem = await penrose.problem({
        constraints: _.flatten(Object.values(constraints))
      });

      const result = problem.start({}).run({});

      // Update values
      for (const variable of Object.keys(variables)) {
        const solvedValue = result.vals.get(variables.get(variable)!);
        if (solvedValue === undefined) {
          console.warn(`No solved value for variable ${variable}`);
          continue;
        }
        variables.get(variable)!.val = solvedValue;
      }
    };

    await solveIteration();

    console.log(
      `>>> Variables [SOLVED] (n=${variables.keys().toArray().length}):`,
      window.structuredClone(variables)
    );

    this.#views = _.range(this.time + 1).map((t) => {
      const nodeViews = this.#nodes[t].entries().map(([nodeId, node]) => {
        const style: Record<string, string> = {};
        for (const [key, value] of Object.entries(node.style)) {
          if (value.type === 'variable') {
            const varValue = variables.get(value.varId)!.val;
            const [cssKey, cssValue] = toCSSrule(key, varValue);
            style[cssKey] = cssValue;
          } else if (value.type === 'constant') {
            const [cssKey, cssValue] = toCSSrule(key, value.value);
            style[cssKey] = cssValue;
          } else if (value.type === 'fixed') {
            const [cssKey, cssValue] = toCSSrule(key, value.value);
            style[cssKey] = cssValue;
          }
        }
        return {
          nodeId,
          style,
          css: toCSS(style),
          content: node.content
        } as NodeView;
      });

      return nodeViews.toArray();
    });
  }

  public get views() {
    return this.#views;
  }

  public num = (value: StyleValue | number): penrose.Num => {
    if (typeof value === 'number') {
      return value;
    }

    const styleValue = value as StyleValue;

    if (styleValue.type === 'variable') {
      return this.variable(styleValue.varId);
    }

    if (styleValue.type === 'constant') {
      return styleValue.value as number;
    }
    throw new Error(`Cannot convert ${styleValue.type} to number`);
  };

  private idWithNamespace(key: string, namespace: string): string {
    return `${namespace}-${key}`;
  }
}

export class LayoutCSPScope {
  private namespace: string;
  private layout: LayoutCSP;

  constructor(layout: LayoutCSP, namespace: string) {
    this.namespace = namespace;
    this.layout = layout;
  }

  public variable(id: string): Variable {
    return this.layout.variable(this.namespace, id);
  }

  public constraint(id: string): Constraint {
    return this.layout.constraint(this.namespace, id);
  }
}
