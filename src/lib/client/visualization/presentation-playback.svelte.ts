/** Reactive playback position shared by presentation controls and retained references. */

export class PresentationPlayback {
  #selectionKey = $state('');
  #step = $state(0);

  stepFor(selectionKey: string): number {
    return this.#selectionKey === selectionKey ? this.#step : 0;
  }

  seek(selectionKey: string, step: number): void {
    this.#selectionKey = selectionKey;
    this.#step = Math.max(0, step);
  }
}
