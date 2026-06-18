import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'vitest/config';
import { playwright } from '@vitest/browser-playwright';
import { sveltekit } from '@sveltejs/kit/vite';
import { createLogger } from 'vite';

const logger = createLogger();
const originalWarn = logger.warn;

logger.warn = (msg, options) => {
  const text = typeof msg === 'string' ? msg : String(msg);

  if (text.includes('Failed to load source map') && text.includes('.pnpm/@penrose+core')) {
    return;
  }

  originalWarn(msg, options);
};

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
  customLogger: logger,
  plugins: [tailwindcss(), sveltekit(), MDHmr()],
  optimizeDeps: {
    exclude: ['@penrose/core'],
    include: [
      '@penrose/core > @datastructures-js/queue',
      '@penrose/core > consola',
      '@penrose/core > immutable',
      '@penrose/core > lodash',
      '@penrose/core > mathjax-full/js/mathjax.js',
      '@penrose/core > mathjax-full/js/handlers/html.js',
      '@penrose/core > mathjax-full/js/adaptors/browserAdaptor.js',
      '@penrose/core > mathjax-full/js/output/svg.js',
      '@penrose/core > mathjax-full/js/input/tex.js',
      '@penrose/core > mathjax-full/js/input/tex/AllPackages.js',
      '@penrose/core > ml-matrix',
      '@penrose/core > moo',
      '@penrose/core > nearley',
      '@penrose/core > pandemonium',
      '@penrose/core > poly-partition',
      '@penrose/core > recursive-diff',
      // '@penrose/core > rose', // should be excluded (wasm)
      '@penrose/core > seedrandom',
      '@penrose/core > true-myth'
    ]
  },
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
          name: 'client',
          browser: {
            enabled: true,
            provider: playwright(),
            instances: [{ browser: 'chromium', headless: true }]
          },
          include: ['src/**/*.svelte.{test,spec}.{js,ts}'],
          exclude: ['src/lib/server/**']
        }
      },

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
