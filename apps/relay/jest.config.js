/**
 * Jest 配置文件
 */

export default {
  rootDir: '../..',

  // 测试环境
  testEnvironment: 'node',

  // 测试文件匹配模式
  testMatch: [
    '<rootDir>/apps/relay/test/**/*.test.ts',
    '<rootDir>/apps/relay/test/**/*.spec.ts'
  ],

  // 忽略的文件和目录
  testPathIgnorePatterns: [
    '<rootDir>/node_modules/',
    '<rootDir>/apps/relay/dist/'
  ],

  // TypeScript 支持配置
  preset: 'ts-jest',
  transform: {
    '^.+\\.[tj]s$': ['ts-jest', {
      useESM: true,
      tsconfig: '<rootDir>/apps/relay/tsconfig.json',
    }],
  },
  extensionsToTreatAsEsm: ['.ts'],

  // 模块路径映射
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/apps/relay/src/$1',
    '^@test/(.*)$': '<rootDir>/apps/relay/test/$1',
    '^@cicada/shared$': '<rootDir>/packages/shared/src',
    '^@cicada/shared/(.*)$': '<rootDir>/packages/shared/src/$1',
    '^(\\.{1,2}/.*)\\.js$': '$1',
  },

  // 模块文件扩展名
  moduleFileExtensions: ['ts', 'js', 'json'],

  // 覆盖率配置
  collectCoverage: false,
  collectCoverageFrom: [
    'apps/relay/src/**/*.ts',
    'packages/shared/src/validators/**/*.ts',
    '!apps/relay/src/**/*.d.ts',
    '!apps/relay/src/types/**',
    '!apps/relay/src/api/index.ts',
    '!apps/relay/src/domain/**/index.ts',
    '!apps/relay/src/infrastructure/**/index.ts',
    '!apps/relay/src/presentation/**/index.ts',
    '!apps/relay/src/infrastructure/crypto/**',
    '!apps/relay/src/infrastructure/logger/filters.ts',
    '!apps/relay/src/infrastructure/logger/formatters.ts',
    '!apps/relay/src/infrastructure/persistence/repositories/**',
    '!apps/relay/src/utils/debug-formatters.ts',
    '!apps/relay/src/utils/logger.ts',
  ],

  // 覆盖率报告格式
  coverageReporters: [
    'text',
    'lcov',
    'html',
    'json-summary'
  ],

  // 覆盖率输出目录
  coverageDirectory: '<rootDir>/apps/relay/coverage',

  // 覆盖率阈值
  coverageThreshold: {
    global: {
      branches: 70,
      functions: 70,
      lines: 70,
      statements: 70
    }
  },

  // 设置文件
  setupFilesAfterEnv: ['<rootDir>/apps/relay/test/setup.ts'],

  // 清理模拟
  clearMocks: true,
  restoreMocks: true,

  // 详细输出
  verbose: true,

  // 测试超时
  testTimeout: 10000,

  // 错误处理
  errorOnDeprecated: true,

};
