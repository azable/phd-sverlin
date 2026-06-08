import * as penrose from '@penrose/core';
import * as _ from 'lodash-es';
import { Node, type NodeView, type NodeConfig, type StyleValue } from './node.svelte';
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

  #nodes: SvelteMap<string, Node>[] = [new SvelteMap()];
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
    await tick();
    return layout;
  }

  private ensureRoot() {
    if (this.#root === undefined) {
      throw new Error('Root node is not defined.');
    }
  }

  private async node(config: NodeConfig, content?: string): Promise<string> {
    this.ensureRoot();
    const nodeId = `node-${this.#nodeIdCounter++}`;
    const node = await Node.create(this, nodeId, config, content);
    this.#nodes[this.time].set(node.id, node);
    node.within(this.#root!);
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

  // private ensureUniqId(id: string | undefined): string {
  //   if (id === undefined || id === null) {
  //     // throw new Error('ID must be provided for variable/constraint');
  //     return randomUUID();
  //   }
  //   return id;
  // }

  public variable(namespace: string, id: string): Variable {
    id = this.idWithNamespace(id, namespace);
    if (!this.#variables.has(id)) {
      this.#variables.set(id, new Variable(id));
    }
    return this.#variables.get(id)!;
  }

  public constraint(namespace: string, id: string): Constraint {
    id = this.idWithNamespace(id, namespace);
    if (!this.#constraints.has(id)) {
      const constraint = new Constraint(id);
      this.#constraints.set(id, constraint);
      return constraint;
    }
    return this.#constraints.get(id)!;
  }

  public async solve() {
    this.ensureRoot();

    const nodes = this.#nodes.map((nodeMap) => ({
      root: this.#root!.asObject(),
      ...Object.fromEntries(nodeMap.entries().map(([id, node]) => [id, node.asObject()]))
    }));
    console.log(nodes);
    const variables = this.#variables.keys().reduce(
      (acc, key) => {
        acc[key] = this.#variables.get(key)!;
        return acc;
      },
      {} as Record<string, Variable>
    );
    const constraints = Object.fromEntries(
      this.#constraints.entries().map(([id, constraint]) => [id, constraint.expr])
    );

    // Randomize initial variable values to help solver escape local minima
    for (const v of _.values(variables)) {
      v.val = Math.random() * (v.randomInit.max - v.randomInit.min) + v.randomInit.min;
    }

    console.log('====================== SOLVE ======================');
    console.log(
      `>>> Nodes (time steps=${nodes.length},`,
      `total nodes=${_.sumBy(nodes, (n) => Object.keys(n).length)}):`,
      window.structuredClone(nodes)
    );
    console.log(
      `>>> Variables (n=${Object.keys(variables).length}):`,
      window.structuredClone(variables)
    );
    console.log(
      `>>> Constraints (n=${Object.keys(constraints).length}):`,
      window.structuredClone(constraints)
    );

    const solveIteration = async () => {
      const problem = await penrose.problem({
        constraints: _.values(constraints)
      });

      const result = problem.start({}).run({});
      console.log('>>> Solver result:', result);

      // Update values
      for (const variable of Object.keys(variables)) {
        const solvedValue = result.vals.get(variables[variable]);
        if (solvedValue === undefined) {
          console.warn(`No solved value for variable ${variable}`);
          continue;
        }
        variables[variable].val = solvedValue;
      }
    };

    await solveIteration();

    console.log(
      `>>> Variables [SOLVED] (n=${Object.keys(variables).length}):`,
      window.structuredClone(variables)
    );

    this.#views = _.range(this.time + 1).map((t) => {
      const nodeViews = _.entries(nodes[t]).map(([nodeId, node]) => {
        const style = Object.fromEntries(
          _.entries(node.style).map(([key, value]) => {
            if (value.type === 'variable') {
              const varValue = variables[value.varId].val;
              return toCSSrule(key, varValue);
            } else {
              return toCSSrule(key, value.value);
            }
          })
        );
        console.log(style);
        return {
          nodeId,
          style,
          css: toCSS(style),
          content: node.content
        } as NodeView;
      });

      return nodeViews;
    });
  }

  public get views() {
    return this.#views;
  }

  private idWithNamespace(key: string, namespace: string): string {
    return `${namespace}-${key}`;
  }

  public num = (value: StyleValue | number): penrose.Num => {
    if (typeof value === 'number') {
      return value;
    }

    const styleValue = value as StyleValue;

    if (styleValue.type === 'variable') {
      if (!this.#variables.has(styleValue.varId)) {
        throw new Error(`Variable with id ${styleValue.varId} does not exist`);
      }
      return this.#variables.get(styleValue.varId)!;
    }

    if (styleValue.type === 'constant') {
      return styleValue.value as number;
    }
    throw new Error(`Cannot convert ${styleValue.type} to number`);
  };
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
