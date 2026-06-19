import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'vitest/config';
import { sveltekit } from '@sveltejs/kit/vite';

function MDHmr() {
  return {
    name: 'static-hmr',
    enforce: 'post' as const,
    handleHotUpdate({ file, server }: any) {
      if (file.includes('static/')) {
        server.ws.send({
          type: 'full-reload',
          path: '*'
        });
      }
    }
  };
}

export default defineConfig({
  plugins: [tailwindcss(), sveltekit(), MDHmr()],
  server: {
    host: true,
    port: 5173,
    strictPort: true,
    sourcemapIgnoreList(sourcePath) {
      return sourcePath.includes('node_modules');
    }
  },
  test: {
    expect: { requireAssertions: true },
    projects: [
      {
        extends: './vite.config.ts',
        test: {
          name: 'server',
          environment: 'node',
          include: ['src/**/*.{test,spec}.{js,ts}'],
          exclude: ['src/**/*.svelte.{test,spec}.{js,ts}']
        }
      }
    ]
  }
});
