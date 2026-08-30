export type PollSnapshot<Value> = { base: Value; value: Value };

/** Use a poll result only while its originating page data is still authoritative. */
export function selectPollSnapshot<Value>(pageValue: Value, snapshot?: PollSnapshot<Value>): Value {
  return snapshot?.base === pageValue ? snapshot.value : pageValue;
}

/** Discard a response when an action invalidated its originating page data in flight. */
export function completePollSnapshot<Value>(
  base: Value,
  current: Value,
  value: Value
): PollSnapshot<Value> | undefined {
  return base === current ? { base, value } : undefined;
}
