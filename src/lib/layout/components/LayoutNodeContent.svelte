<script lang="ts">
  export type NodeContentProps = {
    text: string;
    css: string;
  };

  let { text, css }: NodeContentProps = $props();
</script>

<div class="node-content" style={css}>
  {text}
</div>

<style>
  .node-content {
    user-select: none;
  }
</style>
