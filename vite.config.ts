import tailwindcss from '@tailwindcss/vite';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { defineConfig } from 'vitest/config';
import { sveltekit } from '@sveltejs/kit/vite';
import type { HmrContext, Plugin } from 'vite';

const exampleCatalog = JSON.parse(
  readFileSync(new URL('./examples/catalog.json', import.meta.url), 'utf8')
) as { templates: { file: string; id: string }[] };

function MDHmr(): Plugin {
  return {
    name: 'static-hmr',
    enforce: 'post' as const,
    handleHotUpdate({ file, server }: HmrContext) {
      if (file.includes('static/')) {
        server.ws.send({
          type: 'full-reload',
          path: '*'
        });
      }
    }
  };
}

function exampleHmr(): Plugin {
  return {
    name: 'sverlin-example-hmr',
    apply: 'serve',
    configureServer(server) {
      const files = new Map(
        exampleCatalog.templates.map(({ file, id }) => [path.resolve('examples', file), id])
      );
      server.watcher.add([...files.keys()]);
      const notify = (event: string, file: string) => {
        if (event !== 'change' && event !== 'add' && event !== 'unlink') return;
        const id = files.get(path.resolve(file));
        if (id) server.ws.send({ type: 'custom', event: 'sverlin:example-changed', data: { id } });
      };
      server.watcher.on('all', notify);
      server.httpServer?.once('close', () => server.watcher.off('all', notify));
    }
  };
}

export default defineConfig({
  cacheDir: '.cache/vite',
  plugins: [tailwindcss(), sveltekit(), MDHmr(), exampleHmr()],
  server: {
    host: true,
    port: 5173,
    strictPort: true,
    watch: {
      // Toolchain symlinks and generated state can exhaust Linux file watchers.
      ignored: ['**/{.devenv,.direnv,.cache,.local,.stack-work,outputs,tmp}/**']
    },
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
