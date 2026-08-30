import prettier from 'eslint-config-prettier';
import path from 'node:path';
import { includeIgnoreFile } from '@eslint/compat';
import js from '@eslint/js';
import svelte from 'eslint-plugin-svelte';
import { defineConfig } from 'eslint/config';
import globals from 'globals';
import ts from 'typescript-eslint';
import svelteConfig from './svelte.config.js';

const gitignorePath = path.resolve(import.meta.dirname, '.gitignore');

export default defineConfig(
  includeIgnoreFile(gitignorePath),
  js.configs.recommended,
  ...ts.configs.recommended,
  ...svelte.configs.recommended,
  prettier,
  ...svelte.configs.prettier,
  {
    languageOptions: { globals: { ...globals.browser, ...globals.node } },
    rules: {
      // typescript-eslint strongly recommend that you do not use the no-undef lint rule on TypeScript projects.
      // see: https://typescript-eslint.io/troubleshooting/faqs/eslint/#i-get-errors-from-the-no-undef-rule-about-global-variables-not-being-defined-even-though-there-are-no-typescript-errors
      'no-undef': 'off',
      'require-yield': 'off',
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_'
        }
      ]
    }
  },
  {
    files: ['**/*.svelte', '**/*.svelte.ts', '**/*.svelte.js'],
    languageOptions: {
      parserOptions: {
        projectService: true,
        extraFileExtensions: ['.svelte'],
        parser: ts.parser,
        svelteConfig
      }
    }
  },
  {
    files: ['src/lib/client/components/ui/**/*.svelte'],
    rules: {
      'svelte/no-navigation-without-resolve': 'off'
    }
  },
  {
    files: ['src/**/*.ts', 'src/**/*.svelte'],
    ignores: ['src/lib/client/components/ui/**', 'src/lib/shared/visualization/generated/**'],
    rules: {
      '@typescript-eslint/explicit-module-boundary-types': 'error'
    }
  },
  {
    files: ['src/lib/shared/**/*.{ts,js}'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: ['$lib/client/**', '$lib/server/**', '$app/**', '$env/**', 'node:*', 'svelte'],
              message: 'Shared contracts and projections must remain environment-neutral.'
            }
          ]
        }
      ]
    }
  },
  {
    files: ['src/lib/client/**/*.{ts,js,svelte}'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: ['$lib/server/**', '$env/**', 'node:*'],
              message: 'Client modules cannot depend on server-only code.'
            }
          ]
        }
      ]
    }
  },
  {
    files: ['src/lib/server/**/*.{ts,js}'],
    ignores: ['src/lib/server/compiler/**'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: ['$lib/client/**'],
              message: 'Server modules cannot depend on browser-only code.'
            },
            {
              group: ['$lib/server/compiler/*', '$lib/server/compiler/**'],
              message: 'Use the public $lib/server/compiler service boundary.'
            }
          ]
        }
      ]
    }
  }
);
