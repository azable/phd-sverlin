import { mount, unmount } from 'svelte';
import NodeContentComponent, { type NodeContentProps } from './components/LayoutNodeContent.svelte';

export type ClientSize = {
  clientWidth: number;
  clientHeight: number;
};

function nextFrame() {
  return new Promise<void>((resolve) => {
    requestAnimationFrame(() => resolve());
  });
}

export async function measureContent(props: NodeContentProps): Promise<ClientSize> {
  const host = document.createElement('div');

  host.style.position = 'absolute';
  host.style.visibility = 'hidden';
  host.style.pointerEvents = 'none';
  host.style.left = '-10000px';
  host.style.top = '-10000px';
  host.style.width = 'max-content';

  document.body.appendChild(host);

  const component = mount(NodeContentComponent, {
    target: host,
    props
  });

  await nextFrame();

  const element = host.firstElementChild as HTMLElement | null;

  const rect = element ? element.getBoundingClientRect() : host.getBoundingClientRect();

  unmount(component);
  host.remove();

  return {
    clientWidth: rect.width,
    clientHeight: rect.height
  };
}
