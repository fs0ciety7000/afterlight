import js from '@eslint/js';
import reactHooks from 'eslint-plugin-react-hooks';
import globals from 'globals';
import tseslint from 'typescript-eslint';

const forbidden = (names, why) => names.map((name) => ({ name, message: why }));

export default tseslint.config(
  { ignores: ['dist', 'node_modules', '.claude', 'playwright-report', 'test-results'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.{ts,tsx}'],
    languageOptions: { globals: { ...globals.browser } },
    plugins: { 'react-hooks': reactHooks },
    rules: { ...reactHooks.configs.recommended.rules },
  },
  // Architecture guard: the engine is pure TypeScript (no UI, renderer, store or storage).
  {
    files: ['src/engine/**/*.ts'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          paths: forbidden(
            ['react', 'react-dom', 'phaser', 'zustand', 'idb', 'immer'],
            'src/engine must stay pure TypeScript (see docs/ARCHITECTURE.md).',
          ),
          patterns: [
            {
              group: ['@/app/*', '@/ui/*', '@/renderer/*', '@/state/*', '@/persistence/*'],
              message: 'The engine must not depend on outer layers.',
            },
          ],
        },
      ],
      'no-restricted-globals': ['error', 'window', 'document', 'localStorage', 'performance'],
      'no-restricted-properties': [
        'error',
        { object: 'Math', property: 'random', message: 'Use the seeded RNG from src/engine/core/rng.ts.' },
        { object: 'Date', property: 'now', message: 'Time is passed in as a parameter.' },
      ],
    },
  },
  // The renderer draws; it never owns the authoritative state.
  {
    files: ['src/renderer/**/*.ts'],
    rules: {
      'no-restricted-imports': [
        'error',
        { paths: forbidden(['zustand', 'idb'], 'The renderer only listens to engine events.') },
      ],
    },
  },
  { files: ['*.config.{js,ts}', 'tests/**/*.ts'], languageOptions: { globals: { ...globals.node } } },
);
