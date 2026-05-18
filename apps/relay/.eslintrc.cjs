module.exports = {
  parser: '@typescript-eslint/parser',
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended'
  ],
  plugins: ['@typescript-eslint'],
  parserOptions: {
    ecmaVersion: 2022,
    sourceType: 'module'
    // project: './tsconfig.json' // 暂时禁用，因为 test/ 目录不在 tsconfig 中
  },
  env: {
    node: true,
    es2022: true
  },
  rules: {
    // TypeScript 规则
    '@typescript-eslint/no-explicit-any': 'warn',
    '@typescript-eslint/no-unused-vars': ['warn', {  // 改为 warn，不阻塞开发
      argsIgnorePattern: '^_',
      varsIgnorePattern: '^_'
    }],
    '@typescript-eslint/explicit-function-return-type': 'off',
    '@typescript-eslint/explicit-module-boundary-types': 'off',
    '@typescript-eslint/no-non-null-assertion': 'warn',
    
    // 一般规则
    'no-console': 'off',  // 关闭 console 警告（项目中大量使用）
    'prefer-const': 'error',
    'no-var': 'error',
    'eqeqeq': ['error', 'always'],
    'curly': ['error', 'all'],
    'brace-style': ['error', '1tbs'],
    
    // 代码质量
    'no-debugger': 'error',
    'no-alert': 'error',
    'no-eval': 'error',
    'no-implied-eval': 'error',
    'no-return-await': 'warn',  // 改为 warn
    'require-await': 'off',  // 关闭（某些方法需要保持 async 接口）
    
    // 可读性
    'max-len': ['warn', { 
      code: 120,
      ignoreComments: true,
      ignoreStrings: true,
      ignoreTemplateLiterals: true
    }],
    'no-multiple-empty-lines': ['error', { max: 2, maxEOF: 1 }],
    'semi': ['error', 'always'],
    'quotes': ['error', 'single', { avoidEscape: true }],
    'comma-dangle': ['error', 'only-multiline']
  },
  ignorePatterns: [
    'node_modules/',
    'dist/',
    'coverage/',
    '.wrangler/',
    '*.js',
    '!.eslintrc.js',
    '!jest.config.js'
  ]
};
