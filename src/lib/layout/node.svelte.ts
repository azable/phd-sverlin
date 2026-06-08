import * as _ from 'lodash-es';
import * as penrose from '@penrose/core';
import { LayoutCSP, LayoutCSPScope, Variable } from './layout.svelte';
import { lessThan } from './constraints.svelte';
import { measureContent, type ClientSize } from './node-content';
import { styleValuesToDefaultCSSrules, toCSS } from './style';

export type NodeConfig = {
  style: Record<string, string | number | Variable>;
};

export type StyleValue =
  | {
      type: 'variable';
      varId: string;
    }
  | {
      type: 'constant';
      value: number;
    }
  | {
      type: 'fixed';
      value: string;
    };

export type NodeView = {
  nodeId: string;
  style: Record<string, string>;
  css: string;
  content?: NodeContent;
};

const NODE_HANDLE_ID: unique symbol = Symbol('NodeHandle.id');

export type NodeStyleValue = string | number | Variable;

export type NodeStyle = Record<string, NodeStyleValue>;

export type DefaultStyleFields = {
  left: Variable;
  top: Variable;
  width: Variable;
  height: Variable;
};

export type WithDefaultStyle<StyleT extends NodeStyle> = DefaultStyleFields & StyleT;

type VariableFields<T extends Record<string, unknown>> = {
  [K in keyof T as T[K] extends Variable ? K : never]: T[K];
};

export type NodeHandle<StyleT extends NodeStyle> = VariableFields<StyleT> & {
  readonly [NODE_HANDLE_ID]: string;
};

export type AnyStyledNodeHandle = NodeHandle<NodeStyle>;

export function getNodeHandleId(handle: AnyStyledNodeHandle): string {
  return handle[NODE_HANDLE_ID];
}

function makeNodeHandle<StyleT extends NodeStyle>(
  nodeId: string,
  style: StyleT
): NodeHandle<StyleT> {
  const result: Record<string, Variable> = {};

  for (const [key, value] of Object.entries(style)) {
    if (value instanceof Variable) {
      result[key] = value;
    }
  }

  Object.defineProperty(result, NODE_HANDLE_ID, {
    value: nodeId,
    enumerable: false
  });

  Object.defineProperty(result, 'id', {
    value: nodeId,
    enumerable: true
  });

  return result as NodeHandle<StyleT>;
}

export type NodeContent = {
  text: string;
};

export class Node<StyleT extends NodeStyle = NodeStyle> {
  #layout: LayoutCSP;
  #scope: LayoutCSPScope;

  #id: string;
  #rawStyle: StyleT;
  #style: Record<keyof StyleT, StyleValue>;
  #content: NodeContent = $state({
    text: ''
  });

  private constructor(layout: LayoutCSP, id: string, scope: LayoutCSPScope, rawStyle: StyleT) {
    this.#layout = layout;
    this.#id = id;
    this.#scope = scope;
    this.#rawStyle = rawStyle;

    this.#style = _.mapValues(rawStyle, (value, key) => {
      if (value instanceof Variable) {
        return {
          type: 'variable',
          varId: value.id
        } satisfies StyleValue;
      }

      if (typeof value === 'number') {
        return {
          type: 'constant',
          value
        } satisfies StyleValue;
      }

      if (typeof value === 'string') {
        return {
          type: 'fixed',
          value
        } satisfies StyleValue;
      }

      throw new Error(`Invalid style value for key ${String(key)}`);
    }) as Record<keyof StyleT, StyleValue>;
  }

  public static async create<InputStyleT extends NodeStyle>(
    layout: LayoutCSP,
    id: string,
    config: { style: InputStyleT },
    content?: string
  ): Promise<Node<WithDefaultStyle<InputStyleT>>> {
    const scope = new LayoutCSPScope(layout, id);

    const rawStyle = {
      width: config.style.width ?? scope.variable('width'),
      height: config.style.height ?? scope.variable('height'),
      left: config.style.left ?? scope.variable('left'),
      top: config.style.top ?? scope.variable('top'),
      ...config.style
    } as WithDefaultStyle<InputStyleT>;

    const node = new Node(layout, id, scope, rawStyle);

    if (content !== undefined) {
      const { clientWidth, clientHeight } = await node.setContent(content);
      const { width, height } = node.bounds();

      node.#scope
        .constraint('min-width')
        .set(lessThan(node.#layout.num(clientWidth), width, node.#layout.unitSize));

      node.#scope
        .constraint('min-height')
        .set(lessThan(node.#layout.num(clientHeight), height, node.#layout.unitSize));
    }

    return node;
  }

  public get id() {
    return this.#id;
  }

  public get rawStyle(): StyleT {
    return this.#rawStyle;
  }

  public get style(): Record<keyof StyleT, StyleValue> {
    return this.#style;
  }

  public get handle(): NodeHandle<StyleT> {
    return makeNodeHandle(this.#id, this.#rawStyle);
  }

  public get content() {
    return this.#content;
  }

  public asObject() {
    return {
      id: this.#id,
      style: this.#style,
      content: { ...this.#content }
    };
  }

  public within(container: Node) {
    const { left, top, right, bottom } = this.bounds();
    const { left: cLeft, top: cTop, right: cRight, bottom: cBottom } = container.bounds();

    this.#scope.constraint('within-left').set(lessThan(cLeft, left, 0));
    this.#scope.constraint('within-top').set(lessThan(cTop, top, 0));
    this.#scope.constraint('within-right').set(lessThan(right, cRight, 0));
    this.#scope.constraint('within-bottom').set(lessThan(bottom, cBottom, 0));

    return this;
  }

  public bounds(): Record<string, penrose.Num> {
    const left = this.#layout.num(this.style.left);
    const top = this.#layout.num(this.style.top);
    const width = this.#layout.num(this.style.width);
    const height = this.#layout.num(this.style.height);
    const right = penrose.add(left, width);
    const bottom = penrose.add(top, height);

    return {
      left,
      top,
      right,
      bottom,
      width,
      height
    };
  }

  private async setContent(content: string): Promise<ClientSize> {
    this.#content.text = content;
    const styleValues = styleValuesToDefaultCSSrules(this.style);
    return await measureContent({
      text: this.#content.text,
      css: toCSS(styleValues)
    });
  }
}
