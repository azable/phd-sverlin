<script lang="ts">
  import { resolve } from '$app/paths';

  import * as AlertDialog from '$lib/client/components/ui/alert-dialog';
  import { Button } from '$lib/client/components/ui/button';

  type Props = { open: boolean };
  let { open }: Props = $props();
</script>

<AlertDialog.Root {open}>
  <AlertDialog.Content onEscapeKeydown={(event) => event.preventDefault()}>
    <AlertDialog.Header>
      <AlertDialog.Title>Time is up</AlertDialog.Title>
      <AlertDialog.Description>
        This phase has ended. Your work has been saved and this project is now read-only.
      </AlertDialog.Description>
    </AlertDialog.Header>
    <AlertDialog.Footer>
      <form method="POST" action={resolve('/study')}>
        <Button type="submit">Continue study</Button>
      </form>
    </AlertDialog.Footer>
  </AlertDialog.Content>
</AlertDialog.Root>
