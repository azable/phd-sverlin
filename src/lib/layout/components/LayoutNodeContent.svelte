<script lang="ts">
  export type NodeContentProps = {
    text: string;
  };

  let { text }: NodeContentProps = $props();
</script>

<div class="node-content">
  {text}
</div>

<style>
  .node-content {
    user-select: none;
  }
</style>
