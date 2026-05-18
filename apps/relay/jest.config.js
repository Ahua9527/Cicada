/**
 * Jest 配置文件
 */

export default {
  // 测试环境
  testEnvironment: 'node',

  // 测试文件匹配模式
  testMatch: [
    '<rootDir>/test/**/*.test.ts',
    '<rootDir>/test/**/*.spec.ts'
  ],

  // 忽略的文件和目录
  testPathIgnorePatterns: [
    '<rootDir>/node_modules/',
    '<rootDir>/dist/'
  ],

  // TypeScript 支持配置
  preset: 'ts-jest',
  transform: {
    '^.+\\.ts$': ['ts-jest', {
      useESM: true,
    }],
  },
  extensionsToTreatAsEsm: ['.ts'],

  // 模块路径映射
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
    '^@test/(.*)$': '<rootDir>/test/$1',
    '^@cicada/shared$': '<rootDir>/../../packages/shared/src',
    '^@cicada/shared/(.*)$': '<rootDir>/../../packages/shared/src/$1',
    '^(\\.{1,2}/.*)\\.js$': '$1',
  },

  // 模块文件扩展名
  moduleFileExtensions: ['ts', 'js', 'json'],

  // 覆盖率配置
  collectCoverage: false,
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.d.ts',
    '!src/types/**',
    '!src/api/index.ts',
    '!src/domain/**/index.ts',
    '!src/infrastructure/**/index.ts',
    '!src/presentation/**/index.ts',
  ],

  // 覆盖率报告格式
  coverageReporters: [
    'text',
    'lcov',
    'html',
    'json-summary'
  ],

  // 覆盖率输出目录
  coverageDirectory: 'coverage',

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
  setupFilesAfterEnv: ['<rootDir>/test/setup.ts'],

  // 清理模拟
  clearMocks: true,
  restoreMocks: true,

  // 详细输出
  verbose: true,

  // 测试超时
  testTimeout: 10000,

  // 错误处理
  errorOnDeprecated: true,

  // 全局变量
  globals: {
    'ts-jest': {
      tsconfig: 'tsconfig.json'
    }
  }
};
