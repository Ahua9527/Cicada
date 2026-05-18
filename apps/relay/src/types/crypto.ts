/**
 * API Key 认证配置
 */
export interface ApiKeyConfig {
  minLength: number;
  maxLength: number;
  allowedPattern: RegExp;
  rotationInterval: number;
}

/**
 * 时间戳验证配置
 */
export interface TimestampConfig {
  maxAge: number; // 最大有效期（秒）
  clockSkewTolerance: number; // 时钟偏差容忍度（秒）
}

/**
 * Nonce验证配置
 */
export interface NonceConfig {
  minLength: number;
  maxLength: number;
  allowedPattern: RegExp;
  cacheSize: number;
  retentionSize: number;
}

/**
 * 安全配置（API Key 认证）
 */
export interface SecurityConfig {
  apiKey: ApiKeyConfig;
  timestamp: TimestampConfig;
  nonce: NonceConfig;
}

/**
 * API 认证载荷模板
 */
export interface PayloadTemplate {
  command: string;
  connect: string;
  disconnect: string;
}

/**
 * 验证结果
 */
export interface ValidationResult {
  valid: boolean;
  error?: string;
  details?: Record<string, unknown>;
  warning?: string;
}

/**
 * 详细验证结果
 */
export interface DetailedValidationResult extends ValidationResult {
  checks: {
    apiKey: ValidationResult;
    timestamp: ValidationResult;
    nonce: ValidationResult;
    payload: ValidationResult;
  };
  overallRisk: 'low' | 'medium' | 'high';
}

/**
 * API Key 管理
 */
export interface KeyManagement {
  currentKeyId: string;
  keyRotationInterval: number;
  maxKeyAge: number;
  supportedVersions: string[];
}

/**
 * API 认证统计信息
 */
export interface CryptoStats {
  apiKeysValidated: number;
  validationFailures: number;
  replayAttemptsBlocked: number;
  averageVerificationTime: number;
  keyRotations: number;
  lastKeyRotation: number;
}

/**
 * 安全事件
 */
export interface SecurityEvent {
  type: 'api_key_failure' | 'replay_attempt' | 'invalid_timestamp' | 'suspicious_activity';
  timestamp: number;
  deviceId?: string;
  details: Record<string, unknown>;
  severity: 'low' | 'medium' | 'high' | 'critical';
  resolved: boolean;
}
