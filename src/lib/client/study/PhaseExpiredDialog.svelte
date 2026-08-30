<script lang="ts">
  import { resolve } from '$app/paths';

  import * as AlertDialog from '$lib/client/components/ui/alert-dialog';
  import { Button } from '$lib/client/components/ui/button';

  type Props = {
    open: boolean;
    context?: 'participant' | 'admin-preview';
    previewKey?: string;
  };
  let { open, context = 'participant', previewKey }: Props = $props();
</script>

<AlertDialog.Root {open}>
  <AlertDialog.Content onEscapeKeydown={(event) => event.preventDefault()}>
    <AlertDialog.Header>
      <AlertDialog.Title>Time is up</AlertDialog.Title>
      <AlertDialog.Description>
        {context === 'admin-preview'
          ? 'This preview has reached its configured time limit. Restart its timer or return to administration.'
          : 'This phase has ended. Your work has been saved and this project is now read-only.'}
      </AlertDialog.Description>
    </AlertDialog.Header>
    <AlertDialog.Footer>
      {#if context === 'admin-preview' && previewKey}
        <Button href={resolve('/admin')} variant="outline">Return to administration</Button>
        <form method="POST" action="?/restartPreview">
          <input type="hidden" name="previewKey" value={previewKey} />
          <Button type="submit">Restart preview</Button>
        </form>
      {:else}
        <form method="POST" action={resolve('/study')}>
          <Button type="submit">Continue study</Button>
        </form>
      {/if}
    </AlertDialog.Footer>
  </AlertDialog.Content>
</AlertDialog.Root>
