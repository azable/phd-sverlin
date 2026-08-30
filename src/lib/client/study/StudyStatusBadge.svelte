<script lang="ts">
  import { Badge } from '$lib/client/components/ui/badge';

  import {
    studyStatusBadgeVariants,
    studyStatusLabels,
    type StudyDisplayStatus
  } from './study-status';

  type Props = { status: StudyDisplayStatus };
  let { status }: Props = $props();
</script>

<Badge variant={studyStatusBadgeVariants[status]}>{studyStatusLabels[status]}</Badge>
