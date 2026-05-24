/**
 * CicadaRelay 配置管理系统
 *
 * 提供统一的配置管理，支持环境变量覆盖和默认值
 */

import { Env } from '../types';
import {
  API_CONSTANTS,
  SECURITY_CONSTANTS,
  SESSION_CONSTANTS,
  LOG_CONSTANTS,
  METRICS_CONSTANTS,
  WEBSOCKET_CONSTANTS,
  ENV_CONSTANTS,
} from './constants';

// 导出所有常量
export * from './constants';

/**
 * 应用配置接口
 */
export interface AppConfig {
  // 基础配置
  app: {
    name: string;
    version: string;
    environment: string;
    debug: boolean;
  };

  // 安全配置
  security: {
    timestampValidity: number;
    clockSkewTolerance: number;
    nonceMaxLength: number;
    nonceCacheSize: number;
    nonceRetentionSize: number;
  };

  // 会话配置
  session: {
    timeout: number;
    cleanupInterval: number;
    maxConcurrentSessions: number;
    heartbeatInterval: number;
    messageHistorySize: number;
    enableCompression: boolean;
    enableMetrics: boolean;
  };

  // 日志配置
  logging: {
    level: string;
    format: string;
    enableConsole: boolean;
    enableStructured: boolean;
    retentionDays: number;
  };

  // WebSocket配置
  websocket: {
    connectTimeout: number;
    pingInterval: number;
    pongTimeout: number;
    maxFrameSize: number;
    maxMessageQueueSize: number;
  };

  // 监控配置
  monitoring: {
    enableMetrics: boolean;
    enableHealthChecks: boolean;
    metricsInterval: number;
    healthCheckInterval: number;
    alertThresholds: {
      errorRate: number;
      latency: number;
      memoryUsage: number;
    };
  };

  // 性能配置
  performance: {
    enableCompression: boolean;
    compressionThreshold: number;
    enableCaching: boolean;
    cacheSize: number;
    cacheTTL: number;
  };

  // 特性标志配置
  featureFlags: {
    useDddArchitecture: boolean;
  };
}

/**
 * 默认配置
 */
const DEFAULT_CONFIG: AppConfig = {
  app: {
    name: 'CicadaRelay',
    version: API_CONSTANTS.VERSION,
    environment: ENV_CONSTANTS.NODE_ENV.PRODUCTION,
    debug: false,
  },

  security: {
    timestampValidity: SECURITY_CONSTANTS.TIMESTAMP_VALIDITY,
    clockSkewTolerance: SECURITY_CONSTANTS.CLOCK_SKEW_TOLERANCE,
    nonceMaxLength: SECURITY_CONSTANTS.NONCE.MAX_LENGTH,
    nonceCacheSize: SECURITY_CONSTANTS.NONCE.CACHE_SIZE,
    nonceRetentionSize: SECURITY_CONSTANTS.NONCE.RETENTION_SIZE,
  },

  session: {
    timeout: SESSION_CONSTANTS.TIMEOUT,
    cleanupInterval: SESSION_CONSTANTS.CLEANUP_INTERVAL,
    maxConcurrentSessions: SESSION_CONSTANTS.MAX_CONCURRENT_SESSIONS,
    heartbeatInterval: SESSION_CONSTANTS.HEARTBEAT_INTERVAL,
    messageHistorySize: SESSION_CONSTANTS.MESSAGE_HISTORY_SIZE,
    enableCompression: true,
    enableMetrics: true,
  },

  logging: {
    level: LOG_CONSTANTS.LEVELS.INFO,
    format: 'json',
    enableConsole: true,
    enableStructured: true,
    retentionDays: 7,
  },

  websocket: {
    connectTimeout: WEBSOCKET_CONSTANTS.CONNECT_TIMEOUT,
    pingInterval: WEBSOCKET_CONSTANTS.PING_INTERVAL,
    pongTimeout: WEBSOCKET_CONSTANTS.PONG_TIMEOUT,
    maxFrameSize: WEBSOCKET_CONSTANTS.MAX_FRAME_SIZE,
    maxMessageQueueSize: WEBSOCKET_CONSTANTS.MAX_MESSAGE_QUEUE_SIZE,
  },

  monitoring: {
    enableMetrics: true,
    enableHealthChecks: true,
    metricsInterval: 60000, // 1分钟
    healthCheckInterval: 30000, // 30秒
    alertThresholds: {
      errorRate: METRICS_CONSTANTS.THRESHOLDS.ERROR_RATE_WARNING,
      latency: METRICS_CONSTANTS.THRESHOLDS.LATENCY_WARNING,
      memoryUsage: METRICS_CONSTANTS.THRESHOLDS.MEMORY_WARNING,
    },
  },

  performance: {
    enableCompression: true,
    compressionThreshold: 1024, // 1KB
    enableCaching: true,
    cacheSize: 1000,
    cacheTTL: 300000, // 5分钟
  },

  featureFlags: {
    useDddArchitecture: false,
  },
};

/**
 * 配置验证函数
 */
function validateConfig(config: AppConfig): void {
  // 验证数值范围
  if (config.session.timeout < 1000 || config.session.timeout > 3600000) {
    throw new Error('Session timeout must be between 1 second and 1 hour');
  }

  if (config.session.maxConcurrentSessions < 1 || config.session.maxConcurrentSessions > 10000) {
    throw new Error('Max concurrent sessions must be between 1 and 10000');
  }

  if (config.security.timestampValidity < 30 || config.security.timestampValidity > 3600) {
    throw new Error('Timestamp validity must be between 30 seconds and 1 hour');
  }

  // 验证日志级别
  const validLogLevels = Object.values(LOG_CONSTANTS.LEVELS);
  if (!validLogLevels.includes(config.logging.level as any)) {
    throw new Error(
      `Invalid log level: ${config.logging.level}. Valid levels: ${validLogLevels.join(', ')}`
    );
  }
}

/**
 * 从环境变量创建配置
 */
export function createConfig(env: Env): AppConfig {
  const parseNumber = (source: string | undefined, fallback: number): number => {
    if (source === undefined) {
      return fallback;
    }

    const parsed = Number.parseInt(source, 10);
    return Number.isNaN(parsed) ? fallback : parsed;
  };

  const debugFlag = env.DEBUG_MODE;

  const config: AppConfig = {
    ...DEFAULT_CONFIG,

    // 应用基础配置
    app: {
      ...DEFAULT_CONFIG.app,
      environment: env.NODE_ENV ?? DEFAULT_CONFIG.app.environment,
      debug: debugFlag === undefined ? DEFAULT_CONFIG.app.debug : debugFlag === 'true',
    },

    // 安全配置
    security: {
      ...DEFAULT_CONFIG.security,
    },

    // 会话配置
    session: {
      ...DEFAULT_CONFIG.session,
      maxConcurrentSessions: parseNumber(
        env.MAX_CONCURRENT_SESSIONS,
        DEFAULT_CONFIG.session.maxConcurrentSessions
      ),
      timeout: parseNumber(env.SESSION_TIMEOUT, DEFAULT_CONFIG.session.timeout),
    },

    // 日志配置
    logging: {
      ...DEFAULT_CONFIG.logging,
      level: env.LOG_LEVEL ?? DEFAULT_CONFIG.logging.level,
      enableConsole: env.ENABLE_CONSOLE_LOG !== 'false',
      enableStructured: env.ENABLE_STRUCTURED_LOG !== 'false',
    },

    // 特性标志配置
    featureFlags: {
      ...DEFAULT_CONFIG.featureFlags,
      useDddArchitecture: env.USE_DDD_ARCHITECTURE === 'true',
    },

    // WebSocket配置
    websocket: {
      ...DEFAULT_CONFIG.websocket,
      pingInterval: parseNumber(env.WS_PING_INTERVAL, DEFAULT_CONFIG.websocket.pingInterval),
      pongTimeout: parseNumber(env.WS_PONG_TIMEOUT, DEFAULT_CONFIG.websocket.pongTimeout),
    },

    // 监控配置
    monitoring: {
      ...DEFAULT_CONFIG.monitoring,
      enableMetrics: env.ENABLE_METRICS !== 'false',
      enableHealthChecks: env.ENABLE_HEALTH_CHECKS !== 'false',
    },

    // 性能配置
    performance: {
      ...DEFAULT_CONFIG.performance,
      enableCompression: env.ENABLE_COMPRESSION !== 'false',
      enableCaching: env.ENABLE_CACHING !== 'false',
    },
  };

  // 验证配置
  validateConfig(config);

  return config;
}

/**
 * 配置管理器类
 */
export class ConfigManager {
  private static instance: ConfigManager;
  private config: AppConfig;

  private constructor(env: Env) {
    this.config = createConfig(env);
  }

  /**
   * 获取配置管理器实例
   */
  public static getInstance(env?: Env): ConfigManager {
    if (!ConfigManager.instance) {
      if (!env) {
        throw new Error('ConfigManager requires Env on first instantiation');
      }
      ConfigManager.instance = new ConfigManager(env);
    }
    return ConfigManager.instance;
  }

  /**
   * 获取完整配置
   */
  public getConfig(): AppConfig {
    return this.config;
  }

  /**
   * 获取特定配置节
   */
  public get<K extends keyof AppConfig>(key: K): AppConfig[K] {
    return this.config[key];
  }

  /**
   * 更新配置（仅限非环境变量控制的配置）
   */
  public update<K extends keyof AppConfig>(key: K, value: Partial<AppConfig[K]>): void {
    this.config[key] = { ...this.config[key], ...value };
  }

  /**
   * 重置为默认配置
   */
  public reset(): void {
    this.config = { ...DEFAULT_CONFIG };
  }

  /**
   * 验证当前配置
   */
  public validate(): boolean {
    try {
      validateConfig(this.config);
      return true;
    } catch (error) {
      console.error('Configuration validation failed:', error);
      return false;
    }
  }

  /**
   * 获取配置摘要（隐藏敏感信息）
   */
  public getSummary(): AppConfig {
    return this.config;
  }
}

/**
 * 初始化配置的便捷函数
 */
export function initializeConfig(env: Env): ConfigManager {
  return ConfigManager.getInstance(env);
}
