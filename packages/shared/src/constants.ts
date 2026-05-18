// 默认配置
export const DEFAULT_CONFIG = {
  relayURL: 'https://cicada-relay.example.com',
  autoConnect: true,
  showNotifications: true,
} as const;

// WebSocket 配置
export const WEBSOCKET_CONFIG = {
  reconnectInterval: 5000, // 5秒
  maxReconnectAttempts: 10,
  heartbeatInterval: 30000, // 30秒
  connectionTimeout: 10000, // 10秒
} as const;

// 安全配置
export const SECURITY_CONFIG = {
  signatureAlgorithm: 'HMAC-SHA256',
  nonceLength: 16,
  timestampTolerance: 300000, // 5分钟
  maxNonceCache: 1000,
} as const;

// 命令相关常量和工具函数
export * from './constants/commands';

export { LOG_LEVELS, DEFAULT_LOG_LEVEL } from './logger/constants';

// 性能阈值
export const PERFORMANCE_THRESHOLDS = {
  renderTime: 16, // 60fps
  memoryUsage: 100, // 100MB
  renderCount: 1000,
} as const;
