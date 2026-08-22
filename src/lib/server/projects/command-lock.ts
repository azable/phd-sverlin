/**
 * In-process serialization for whole project commands.
 *
 * @packageDocumentation
 */

const commandTails = new Map<string, Promise<void>>();

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
