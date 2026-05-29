import * as _ from 'lodash-es';
import * as penrose from '@penrose/core';
import { LayoutCSP, LayoutCSPScope, type Variable, p } from './layout.svelte';
import { type Temporal } from './temporal';

export type NodeConfig = {
  style: Record<string, string | number | Temporal<Variable>>;
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
  content?: NodeContent;
};

export type NodeContent = {
  text: string;
  clientWidth: number;
  clientHeight: number;
};

export class Node {
  public static all = {} as Record<string, Node>;

  #layout: LayoutCSP;
  #scope: LayoutCSPScope;

  #id: string;
  #style: Record<string, StyleValue>;
  #content: NodeContent = $state({
    text: '',
    clientWidth: 0,
    clientHeight: 0
  });

  constructor(layout: LayoutCSP, config: NodeConfig) {
    this.#layout = layout;
    this.#id = `node-${Object.keys(Node.all).length + 1}`;
    this.#scope = new LayoutCSPScope(layout, this.#id);

    config = {
      style: {
        width: config.style.width ?? this.#scope.varying('width'),
        height: config.style.height ?? this.#scope.varying('height'),
        left: config.style.left ?? this.#scope.varying('left'),
        top: config.style.top ?? this.#scope.varying('top'),
        ...config.style
      }
    };

    this.#style = _.mapValues(config.style, (value, key) => {
      if (typeof value === 'object' && 'at' in value && 'setAt' in value) {
        return {
          type: 'variable',
          varId: value.at(0).id
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

    Node.all[this.#id] = this;

    // Min width/height constraints based on content size
    $effect(() => {
      if (!this.#content) {
        return;
      }

      const { width, height } = this.bounds(0);

      this.#scope
        .constraint('at-least-content-width')
        .setAt(
          0,
          p.lessThanWithPadding(
            p.add(this.#layout.num(this.#content.clientWidth), this.#layout.unitSize),
            width,
            0
          )
        );

      this.#scope
        .constraint('at-least-content-height')
        .setAt(
          0,
          p.lessThanWithPadding(
            p.add(this.#layout.num(this.#content.clientHeight), this.#layout.unitSize),
            height,
            0
          )
        );

      this.#layout.scheduleResolve();
    });

    return this;
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

  public bounds(time: number = this.#layout.time): Record<string, penrose.Num> {
    const left = this.#layout.num(this.style.left, time);
    const top = this.#layout.num(this.style.top, time);
    const width = this.#layout.num(this.style.width, time);
    const height = this.#layout.num(this.style.height, time);
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

  public setContent(content: string) {
    this.#content.text = content;
    return this;
  }
}
