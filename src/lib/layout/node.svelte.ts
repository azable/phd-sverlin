import * as _ from 'lodash-es';
import * as penrose from '@penrose/core';
import { LayoutCSP, LayoutCSPScope, type Variable } from './layout.svelte';
import { lessThan } from './constraints.svelte';
import { measureContent, type ClientSize } from './node-content';

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

export type NodeContent = {
  text: string;
  clientWidth: number;
  clientHeight: number;
};

export class Node {
  #layout: LayoutCSP;
  #scope: LayoutCSPScope;

  #id: string;
  #style: Record<string, StyleValue>;
  #content: NodeContent = $state({
    text: '',
    clientWidth: 0,
    clientHeight: 0
  });

  private constructor(layout: LayoutCSP, id: string, config: NodeConfig) {
    this.#layout = layout;
    this.#id = id;
    this.#scope = new LayoutCSPScope(layout, this.#id);

    config = {
      style: {
        width: config.style.width ?? this.#scope.variable('width'),
        height: config.style.height ?? this.#scope.variable('height'),
        left: config.style.left ?? this.#scope.variable('left'),
        top: config.style.top ?? this.#scope.variable('top'),
        ...config.style
      }
    };

    this.#style = _.mapValues(config.style, (value, key) => {
      if (typeof value === 'object') {
        return {
          type: 'variable',
          varId: value.id
        } as StyleValue;
      } else if (typeof value === 'number') {
        return {
          type: 'constant',
          value
        } as StyleValue;
      } else if (typeof value === 'string') {
        return {
          type: 'fixed',
          value
        } as StyleValue;
      }
      throw new Error(`Invalid style value for key ${key}`);
    });

    // // Min width/height constraints based on content size
    // $effect(() => {
    //   if (!this.#content) {
    //     return;
    //   }

    //   const { width, height } = this.bounds();

    //   this.#scope
    //     .constraint('min-width')
    //     .set(lessThan(this.#layout.num(this.#content.clientWidth), width, this.#layout.unitSize));

    //   this.#scope
    //     .constraint('min-height')
    //     .set(lessThan(this.#layout.num(this.#content.clientHeight), height, this.#layout.unitSize));

    //   this.#layout.scheduleResolve();
    // });

    return this;
  }

  public static async create(
    layout: LayoutCSP,
    id: string,
    config: NodeConfig,
    content?: string
  ): Promise<Node> {
    const node = new Node(layout, id, config);
    if (content !== undefined) {
      const { clientWidth, clientHeight } = await node.setContent(content);
      const { width, height } = node.bounds();

      node.#scope
        .constraint('min-width')
        .set(lessThan(node.#layout.num(clientWidth), width, node.#layout.unitSize));

      node.#scope
        .constraint('min-height')
        .set(lessThan(node.#layout.num(clientHeight), height, node.#layout.unitSize));

      node.#layout.scheduleResolve();
    }
    return node;
  }

  public get id() {
    return this.#id;
  }

  public get content() {
    return this.#content;
  }

  public get style(): Record<string, StyleValue> {
    return this.#style;
  }

  public within(container: Node) {
    const { left, top, right, bottom } = this.bounds();
    const { left: cLeft, top: cTop, right: cRight, bottom: cBottom } = container.bounds();

    this.#scope.constraint('min-left').set(lessThan(cLeft, left));
    this.#scope.constraint('min-top').set(lessThan(cTop, top));
    this.#scope.constraint('max-right').set(lessThan(right, cRight));
    this.#scope.constraint('max-bottom').set(lessThan(bottom, cBottom));

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
    const size = await measureContent({
      text: this.#content.text
    });
    console.log('>>> Measured content size for node', this.#id, size);
    return size;
  }
}
