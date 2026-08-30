import type { BadgeVariant } from '$lib/client/components/ui/badge';
import type { StudyPhaseStatus, StudyProgressStatus } from '$lib/shared/study/projection';

export type StudyDisplayStatus = StudyPhaseStatus | StudyProgressStatus;

export const studyStatusLabels: Record<StudyDisplayStatus, string> = {
  active: 'Active',
  completed: 'Completed',
  'in-progress': 'In progress',
  'not-started': 'Not started',
  'out-of-scope': 'Not previewed',
  pending: 'Pending',
  'ready-to-continue': 'Ready'
};

export const studyStatusBadgeVariants: Record<StudyDisplayStatus, BadgeVariant> = {
  active: 'info',
  completed: 'success',
  'in-progress': 'info',
  'not-started': 'neutral',
  'out-of-scope': 'outline',
  pending: 'neutral',
  'ready-to-continue': 'warning'
};

export const studyStatusSurfaceClasses: Record<StudyDisplayStatus, string> = {
  active: 'bg-status-info/50',
  completed: 'bg-status-success/50',
  'in-progress': 'bg-status-info/50',
  'not-started': 'bg-muted/50',
  'out-of-scope': 'bg-muted/20',
  pending: 'bg-muted/50',
  'ready-to-continue': 'bg-status-warning/50'
};
