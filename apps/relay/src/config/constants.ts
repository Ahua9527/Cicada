/**
 * CicadaRelay 系统常量定义
 *
 * 本文件包含系统中使用的所有常量，避免魔法数字和硬编码值
 */

// API相关常量
export const API_CONSTANTS = {
  // 版本信息
  VERSION: '1.0.0',
  API_VERSION: 'v2',

  // 路径常量
  PATHS: {
    STATUS: '/status',
    HEALTH: '/health',
    DEVICES: '/devices',
    AUTH_CHALLENGE: '/auth/challenge',
    METRICS: '/metrics',
  } as const,

  // HTTP状态码
  HTTP_STATUS: {
    OK: 200,
    CREATED: 201,
    BAD_REQUEST: 400,
    UNAUTHORIZED: 401,
    FORBIDDEN: 403,
    NOT_FOUND: 404,
    METHOD_NOT_ALLOWED: 405,
    TOO_MANY_REQUESTS: 429,
    INTERNAL_SERVER_ERROR: 500,
    SERVICE_UNAVAILABLE: 503,
  } as const,

  // 请求头
  HEADERS: {
    CONTENT_TYPE: 'application/json',
    AUTHORIZATION: 'Authorization',
    USER_AGENT: 'User-Agent',
    X_REQUEST_ID: 'X-Request-ID',
    X_DEVICE_ID: 'X-Device-ID',
    X_FORWARDED_FOR: 'X-Forwarded-For',
  } as const,
} as const;

// 安全相关常量
export const SECURITY_CONSTANTS = {
  // 签名算法
  HMAC_ALGORITHM: 'HMAC' as const,
  HASH_ALGORITHM: 'SHA-256' as const,

  // 载荷模板
  PAYLOAD_TEMPLATES: {
    COMMAND: '{deviceId}:{command}:{timestamp}:{nonce}',
    CONNECT: '{deviceId}:connect:{timestamp}:{nonce}',
    DISCONNECT: '{deviceId}:disconnect:{timestamp}:{nonce}',
    BATCH: '{deviceId}:batch:{timestamp}:{nonce}',
  } as const,

  // 时间戳配置
  TIMESTAMP_VALIDITY: 300, // 5分钟
  CLOCK_SKEW_TOLERANCE: 30, // 30秒

  // Nonce配置
  NONCE: {
    MIN_LENGTH: 8,
    MAX_LENGTH: 128,
    CACHE_SIZE: 10000,
    RETENTION_SIZE: 1000,
    PATTERN: /^[a-zA-Z0-9\-_.]+$/,
  } as const,

  // 签名配置
  SIGNATURE: {
    MIN_LENGTH: 32,
    MAX_LENGTH: 128,
    KEY_ENCODING: 'raw' as const,
    OUTPUT_ENCODING: 'hex' as const,
  } as const,

  // 速率限制
  RATE_LIMITS: {
    COMMANDS_PER_MINUTE: 60,
    CONNECTIONS_PER_MINUTE: 10,
    AUTH_ATTEMPTS_PER_HOUR: 20,
  } as const,
} as const;

// 会话管理常量
export const SESSION_CONSTANTS = {
  // 基础配置
  TIMEOUT: 5 * 60 * 1000, // 5分钟
  CLEANUP_INTERVAL: 60 * 1000, // 1分钟
  MAX_CONCURRENT_SESSIONS: 1000,
  HEARTBEAT_INTERVAL: 30 * 1000, // 30秒
  REGISTRY_DO_NAME: '__cicada_device_registry__',
  AGENT_REGISTRATION_SKEW: 90 * 1000,
  AGENT_ABSENCE_GRACE_MS: 45 * 1000,
  SHORTCUT_COMMAND_TIMEOUT_MS: 20 * 1000,

  // 消息配置
  MESSAGE_HISTORY_SIZE: 100,
  MESSAGE_QUEUE_SIZE: 1000,
  MESSAGE_RETRY_LIMIT: 3,
  MESSAGE_RETRY_DELAY: 1000, // 1秒

  // 存储键
  STORAGE_KEYS: {
    SESSIONS: 'sessions',
    METADATA: 'metadata',
    NONCES: 'nonces',
    DEVICE_REGISTRY: 'device_registry',
    SHORTCUT_GRANTS: 'shortcut_grants',
    MESSAGES: 'messages',
    STATS: 'stats',
    CONFIG: 'config',
    EVENTS: 'events',
    HEALTH_CHECKS: 'health_checks',
  } as const,

  // 状态常量
  STATES: {
    CONNECTING: 'connecting',
    CONNECTED: 'connected',
    DISCONNECTED: 'disconnected',
    SUSPENDED: 'suspended',
    ERROR: 'error',
  } as const,

  // 事件类型
  EVENT_TYPES: {
    CONNECT: 'connect',
    DISCONNECT: 'disconnect',
    MESSAGE: 'message',
    ERROR: 'error',
    TIMEOUT: 'timeout',
    HEARTBEAT: 'heartbeat',
    CLEANUP: 'cleanup',
  } as const,
} as const;

// 日志相关常量
export const LOG_CONSTANTS = {
  // 日志级别
  LEVELS: {
    ERROR: 'error',
    WARN: 'warn',
    INFO: 'info',
    DEBUG: 'debug',
    TRACE: 'trace',
  } as const,

  // 日志格式
  FORMAT: {
    TIMESTAMP: 'YYYY-MM-DD HH:mm:ss.SSS',
    MESSAGE_FORMAT: '[{timestamp}] [{level}] [{requestId}] {message}',
    STRUCTURED_FORMAT: {
      timestamp: true,
      level: true,
      requestId: true,
      deviceId: true,
      sessionId: true,
      error: true,
    },
  } as const,

  // 保留策略
  RETENTION: {
    ERROR_DAYS: 30,
    WARN_DAYS: 7,
    INFO_DAYS: 3,
    DEBUG_HOURS: 24,
    TRACE_HOURS: 1,
  } as const,
} as const;

// 监控和指标常量
export const METRICS_CONSTANTS = {
  // 指标类型
  TYPES: {
    COUNTER: 'counter',
    GAUGE: 'gauge',
    HISTOGRAM: 'histogram',
    TIMER: 'timer',
  } as const,

  // 常用指标
  METRICS: {
    // 连接指标
    CONNECTIONS_TOTAL: 'cicada_relay_connections_total',
    ACTIVE_CONNECTIONS: 'cicada_relay_active_connections',
    CONNECTION_DURATION: 'cicada_relay_connection_duration_seconds',

    // 消息指标
    MESSAGES_TOTAL: 'cicada_relay_messages_total',
    MESSAGE_SIZE: 'cicada_relay_message_size_bytes',
    MESSAGE_LATENCY: 'cicada_relay_message_latency_seconds',

    // 错误指标
    ERRORS_TOTAL: 'cicada_relay_errors_total',
    AUTH_FAILURES_TOTAL: 'cicada_relay_auth_failures_total',
    RATE_LIMIT_EXCEEDED: 'cicada_relay_rate_limit_exceeded_total',

    // 性能指标
    REQUEST_DURATION: 'cicada_relay_request_duration_seconds',
    MEMORY_USAGE: 'cicada_relay_memory_usage_bytes',
    CPU_USAGE: 'cicada_relay_cpu_usage_percent',
  } as const,

  // 聚合窗口
  WINDOWS: {
    MINUTE: 60,
    HOUR: 3600,
    DAY: 86400,
  } as const,

  // 阈值配置
  THRESHOLDS: {
    ERROR_RATE_WARNING: 0.01, // 1%
    ERROR_RATE_CRITICAL: 0.05, // 5%
    LATENCY_WARNING: 1000, // 1秒
    LATENCY_CRITICAL: 5000, // 5秒
    MEMORY_WARNING: 0.8, // 80%
    MEMORY_CRITICAL: 0.9, // 90%
  } as const,
} as const;

// WebSocket相关常量
export const WEBSOCKET_CONSTANTS = {
  // 连接配置
  CONNECT_TIMEOUT: 10000, // 10秒
  PING_INTERVAL: 30000, // 30秒
  PONG_TIMEOUT: 5000, // 5秒
  MAX_FRAME_SIZE: 1024 * 1024, // 1MB
  MAX_MESSAGE_QUEUE_SIZE: 1000,

  // 消息类型
  MESSAGE_TYPES: {
    COMMAND: 'command',
    RESPONSE: 'response',
    PING: 'ping',
    PONG: 'pong',
    ERROR: 'error',
    HEARTBEAT: 'heartbeat',
    DISCONNECT: 'disconnect',
  } as const,

  // 关闭代码
  CLOSE_CODES: {
    NORMAL: 1000,
    GOING_AWAY: 1001,
    PROTOCOL_ERROR: 1002,
    UNSUPPORTED_DATA: 1003,
    NO_STATUS: 1005,
    ABNORMAL: 1006,
    INVALID_DATA: 1007,
    POLICY_VIOLATION: 1008,
    MESSAGE_TOO_BIG: 1009,
    EXTENSION_REQUIRED: 1010,
    INTERNAL_ERROR: 1011,
    SERVICE_RESTART: 1012,
    TRY_AGAIN_LATER: 1013,
  } as const,
} as const;

// 默认命令列表
export const DEFAULT_COMMANDS = {
  SYSTEM: {
    LOCK: 'lock',
    UNLOCK: 'unlock',
    SLEEP: 'sleep',
    WAKE: 'wake',
    RESTART: 'restart',
    SHUTDOWN: 'shutdown',
  },
  BLUETOOTH: {
    ON: 'bt_on',
    OFF: 'bt_off',
    TOGGLE: 'bt_toggle',
    STATUS: 'bt_status',
  },
  DISPLAY: {
    BRIGHTNESS_UP: 'brightness_up',
    BRIGHTNESS_DOWN: 'brightness_down',
    BRIGHTNESS_SET: 'brightness_set',
    SCREENSHOT: 'screenshot',
  },
  AUDIO: {
    MUTE: 'mute',
    UNMUTE: 'unmute',
    VOLUME_UP: 'volume_up',
    VOLUME_DOWN: 'volume_down',
    VOLUME_SET: 'volume_set',
  },
  APPLICATIONS: {
    OPEN: 'app_open',
    CLOSE: 'app_close',
    SWITCH: 'app_switch',
    LIST: 'app_list',
  },
} as const;

// 环境相关常量
export const ENV_CONSTANTS = {
  NODE_ENV: {
    DEVELOPMENT: 'development',
    PRODUCTION: 'production',
    TEST: 'test',
  } as const,

  LOG_LEVELS: {
    ERROR: 'error',
    WARN: 'warn',
    INFO: 'info',
    DEBUG: 'debug',
  } as const,

  DEFAULT_TIMEOUTS: {
    CONNECTION: 10000,
    REQUEST: 30000,
    WEBSOCKET: 120000, // 2分钟
  } as const,
} as const;
