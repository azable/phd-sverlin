import { range } from 'lodash-es';

export class LazyTemporal<T extends object> {
  private values: Record<number, T> = {};
  private instantiator: () => T;

  constructor(instantiator: () => T) {
    this.instantiator = instantiator;
  }

  private ensureInstanceAt(time: number) {
    if (!this.values[time]) {
      this.values[time] = this.instantiator();
    }
  }

  public at(time: number): T {
    this.ensureInstanceAt(time);
    return this.values[time];
  }

  public toSequence(maxTime: number): T[] {
    const times = Object.keys(this.values)
      .map(Number)
      .sort((a, b) => a - b);
    const minTime = times[0];

    return range(0, maxTime + 1).map((t) => {
      if (this.values[t]) {
        return this.values[t];
      } else {
        // If no instance at time t, use the most recent previous instance
        const prevTime = times.filter((time) => time <= t).pop() ?? minTime;
        return this.values[prevTime];
      }
    });
  }
}

export class LazyTemporalMap<K extends string | number, V extends object> {
  private map: Record<K, LazyTemporal<V>> = {} as Record<K, LazyTemporal<V>>;
  private instantiator: (key: K) => LazyTemporal<V>;

  constructor(instantiator: (key: K) => V) {
    this.instantiator = (key) => new LazyTemporal<V>(() => instantiator(key));
  }

  public lookup(key: K): LazyTemporal<V> {
    if (!this.map[key]) {
      this.map[key] = this.instantiator(key);
    }
    return this.map[key];
  }

  public toSequence(maxTime: number): Record<K, V[]> {
    const result: Record<K, V[]> = {} as Record<K, V[]>;
    for (const key in this.map) {
      result[key] = this.map[key].toSequence(maxTime);
    }
    return result;
  }
}
