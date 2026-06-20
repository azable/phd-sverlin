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
    return ['node', element.className, element.exiting ? 'exiting' : undefined]
      .filter(Boolean)
      .join(' ');
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
    background-color: rgb(220, 220, 220);
    background-image:
      linear-gradient(to right, rgba(0, 0, 0, 0.08) 1px, transparent 1px),
      linear-gradient(to bottom, rgba(0, 0, 0, 0.08) 1px, transparent 1px);
    background-size: 20px 20px;
  }

  .node {
    box-sizing: border-box;
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
