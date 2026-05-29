import { range } from 'lodash-es';

class Lazy<T> {
  private instantiator: () => T;

  constructor(instantiator: () => T) {
    this.instantiator = instantiator;
  }

  protected instantiate(): T {
    return this.instantiator();
  }
}

export interface Temporal<T> {
  at(time: number): T;
  setAt(time: number, value: T): void;
  materialize(maxTime: number): T[];
}

export class LazyTemporal<T> extends Lazy<T> implements Temporal<T> {
  private values: Record<number, T> = {};

  constructor(instantiator: () => T) {
    super(instantiator);
  }

  private ensureInstanceAt(time: number) {
    if (!this.values[time]) {
      this.values[time] = this.instantiate();
    }
  }

  public at(time: number): T {
    this.ensureInstanceAt(time);
    return this.values[time];
  }

  public setAt(time: number, value: T) {
    this.values[time] = value;
  }

  public materialize(maxTime: number): T[] {
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

export class LazyUniform<T> extends Lazy<T> implements Temporal<T> {
  private value: T;

  constructor(instantiator: () => T) {
    super(instantiator);
    this.value = this.instantiate();
  }

  public at(time: number): T {
    return this.value;
  }

  public setAt(time: number, value: T) {
    this.value = value;
  }

  public materialize(maxTime: number): T[] {
    const value = this.at(0);
    return range(0, maxTime + 1).map(() => value);
  }
}

type TemporalConstructor<T> = new (instantiator: () => T) => Temporal<T>;

export class LazyTemporalMap<K extends string | number, V> {
  private map: Record<K, Temporal<V>> = {} as Record<K, Temporal<V>>;
  private instantiator: (key: K) => Temporal<V>;

  constructor(TemporalClass: TemporalConstructor<V>, instantiator: (key: K) => V) {
    this.instantiator = (key) => new TemporalClass(() => instantiator(key));
  }

  public lookup(key: K): Temporal<V> {
    if (!this.map[key]) {
      this.map[key] = this.instantiator(key);
    }
    return this.map[key];
  }

  public materialize(maxTime: number): Record<K, V[]> {
    const result: Record<K, V[]> = {} as Record<K, V[]>;
    for (const key in this.map) {
      result[key] = this.map[key].materialize(maxTime);
    }
    return result;
  }
}
