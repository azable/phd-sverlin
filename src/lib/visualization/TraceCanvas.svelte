<script lang="ts">
  import type { LiveElement } from './types';

  let {
    width,
    height,
    elements
  }: {
    width: number;
    height: number;
    elements: LiveElement[];
  } = $props();

  function styleToString(element: LiveElement): string {
    const style = { ...element.style };

    if (element.exiting) {
      style.opacity = 0;
      style.transform = 'scale(0.9)';
      style.pointerEvents = 'none';
    }

    return Object.entries(style)
      .map(([key, value]) => `${camelToKebab(key)}: ${value};`)
      .join(' ');
  }

  function camelToKebab(value: string): string {
    return value.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`);
  }

  function classNameFor(element: LiveElement): string {
    return element.exiting ? 'node exiting' : 'node';
  }
</script>

<div class="canvas" style:width={`${width}px`} style:height={`${height}px`}>
  {#each elements as element (element.id)}
    <div
      class={classNameFor(element)}
      data-render-id={element.id}
      data-block-id={element.blockId}
      data-kind={element.kind}
      style={styleToString(element)}
    >
      {element.content}
    </div>
  {/each}
</div>

<style>
  .canvas {
    position: relative;
    overflow: hidden;
    isolation: isolate;
    background: #fff;
    color: #000;
    font: initial;
    line-height: normal;
  }

  .node {
    box-sizing: border-box;
    border-style: solid;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    user-select: none;

    transition:
      top 300ms ease,
      left 300ms ease,
      width 300ms ease,
      height 300ms ease,
      opacity 300ms ease,
      transform 300ms ease,
      background-color 300ms ease,
      border-color 300ms ease,
      border-radius 300ms ease,
      font-size 300ms ease;
  }
</style>
