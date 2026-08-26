/** Browser-visible maintenance state for the project application. */
export type MaintenanceStatus =
  | { locked: false }
  | { locked: true; lockedAt: string; reason?: string };

/** Stable unlocked state used before the first server check. */
export const unlockedMaintenanceStatus: MaintenanceStatus = { locked: false };
