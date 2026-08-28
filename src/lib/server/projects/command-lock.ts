/**
 * In-process serialization for whole project commands.
 *
 * @packageDocumentation
 */

const commandTailsKey = Symbol.for('sverlin.project-command-tails');
const shared = globalThis as typeof globalThis & {
  [commandTailsKey]?: Map<string, Promise<void>>;
};
const commandTails = (shared[commandTailsKey] ??= new Map());

/**
 * Serialize whole project commands, including slow provider and compiler work.
 * The repository still performs an optimistic head check at every append; this
 * queue only prevents two accepted commands from interleaving their events.
 */
export async function runProjectCommand<T>(
  projectId: string,
  command: () => Promise<T>
): Promise<T> {
  const previous = commandTails.get(projectId) ?? Promise.resolve();
  let release!: () => void;
  const tail = new Promise<void>((resolve) => {
    release = resolve;
  });
  const chain = previous.then(() => tail);
  commandTails.set(projectId, chain);

  await previous;
  try {
    return await command();
  } finally {
    release();
    if (commandTails.get(projectId) === chain) commandTails.delete(projectId);
  }
}
