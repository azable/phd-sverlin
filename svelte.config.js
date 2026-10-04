import adapter from '@sveltejs/adapter-node';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  kit: {
    adapter: adapter(),
    alias: {
      $lib: './src/lib',
      // Editor resolution for the sandbox-only component library; see modes/sverlin/assembly.
      sverlin: './src/lib/modes/sverlin/library'
    }
  },
  compilerOptions: {
    experimental: {
      async: true
    }
  }
};

export default config;
