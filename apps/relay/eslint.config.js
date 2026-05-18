import path from 'node:path';
import { fileURLToPath } from 'node:url';

import js from '@eslint/js';
import tsPlugin from '@typescript-eslint/eslint-plugin';
import tsParser from '@typescript-eslint/parser';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const recommendedTsRules = tsPlugin.configs.recommended?.rules ?? {};

const workerGlobals = {
  console: 'readonly',
  fetch: 'readonly',
  Request: 'readonly',
  Response: 'readonly',
  Headers: 'readonly',
  URL: 'readonly',
  WebSocket: 'readonly',
  WebSocketPair: 'readonly',
  crypto: 'readonly',
  setTimeout: 'readonly',
  clearTimeout: 'readonly',
  setInterval: 'readonly',
  clearInterval: 'readonly',
  DurableObjectState: 'readonly',
  DurableObjectNamespace: 'readonly',
  ExecutionContext: 'readonly'
};

const typescriptConfig = {
  files: ['**/*.ts'],
  languageOptions: {
    parser: tsParser,
    parserOptions: {
      project: './tsconfig.json',
      tsconfigRootDir: __dirname,
      ecmaVersion: 2022,
      sourceType: 'module'
    },
    globals: workerGlobals
  },
  plugins: {
    '@typescript-eslint': tsPlugin
  },
  rules: {
    ...recommendedTsRules,
    '@typescript-eslint/no-unused-vars': [
      'warn',
      {
        argsIgnorePattern: '^_',
        varsIgnorePattern: '^_',
        caughtErrorsIgnorePattern: '^_'
      }
    ],
    '@typescript-eslint/no-explicit-any': 'off',
    '@typescript-eslint/prefer-nullish-coalescing': 'error',
    '@typescript-eslint/no-non-null-assertion': 'off',
    'max-lines': 'off',
    'max-lines-per-function': 'off',
    complexity: 'off',
    'max-depth': 'off',
    'max-nested-callbacks': 'off',
    'max-params': 'off',
    'no-console': 'off',
    eqeqeq: ['error', 'always', { null: 'ignore' }],
    curly: ['error', 'all'],
    'prefer-const': 'error',
    'no-var': 'error'
  }
};

export default [
  js.configs.recommended,
  typescriptConfig,
  {
    files: ['test/**/*.ts', '**/*.test.ts', '**/*.spec.ts'],
    languageOptions: {
      globals: {
        describe: 'readonly',
        it: 'readonly',
        expect: 'readonly',
        beforeEach: 'readonly',
        afterEach: 'readonly',
        beforeAll: 'readonly',
        afterAll: 'readonly',
        jest: 'readonly'
      }
    },
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
      'max-lines': 'off',
      'max-lines-per-function': 'off',
      'no-undef': 'off'
    }
  },
  {
    ignores: [
      'dist/**',
      'node_modules/**',
      'coverage/**',
      '*.tsbuildinfo',
      '.wrangler/**'
    ]
  }
];
