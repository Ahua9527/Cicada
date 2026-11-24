/**
 * CicadaRelay 系统常量定义
 *
 * 本文件包含系统中使用的所有常量，避免魔法数字和硬编码值
 */

// API相关常量
export const API_CONSTANTS = {
  // 版本信息
  VERSION: '1.0.0',
} as const;

// 会话管理常量
export const SESSION_CONSTANTS = {
  // 基础配置
  TIMEOUT: 5 * 60 * 1000, // 5分钟
  CLEANUP_INTERVAL: 60 * 1000, // 1分钟
  REGISTRY_DO_NAME: '__cicada_device_registry__',
  AGENT_REGISTRATION_SKEW: 90 * 1000,
  AGENT_ABSENCE_GRACE_MS: 45 * 1000,
  SHORTCUT_COMMAND_TIMEOUT_MS: 20 * 1000,
  // 一次性注册码：有效 10 分钟；过期或用过的记录再保留 1 天，登记失败时能说清是"已过期"还是"已使用"
  ENROLLMENT_CODE_TTL_MS: 10 * 60 * 1000,
  ENROLLMENT_CODE_RETENTION_MS: 24 * 60 * 60 * 1000,
  MAX_ENROLLMENT_CODES: 100,

  // 存储键
  STORAGE_KEYS: {
    SESSIONS: 'sessions',
    DEVICE_REGISTRY: 'device_registry',
    ENROLLMENT_CODES: 'enrollment_codes',
  } as const,
} as const;
