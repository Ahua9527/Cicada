/**
 * 加密工具模块
 *
 * 提供API Key验证、时间戳验证等安全功能
 */

import { CommandRequest, ValidationResult, DeviceConnectionParams } from '../types';
import type { JsonValue } from '@cicada/shared';

/**
 * 十六进制字符串转换为ArrayBuffer
 */
export function hexToArray(hex: string): ArrayBuffer {
  const result = new ArrayBuffer(hex.length / 2);
  const view = new Uint8Array(result);
  for (let i = 0; i < hex.length; i += 2) {
    view[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return result;
}

/**
 * 将ArrayBuffer转换为十六进制字符串
 */
export function arrayToHex(array: Uint8Array): string {
  return Array.from(array)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * 验证时间戳是否在有效范围内
 * @param timestamp 时间戳（数字或字符串）
 * @param maxAge 最大有效期（秒）
 * @returns boolean 验证结果
 */
export function verifyTimestamp(timestamp: number | string, maxAge: number = 300): boolean {
  const now = Math.floor(Date.now() / 1000);
  // 兼容字符串类型的时间戳（来自 iOS Shortcuts）
  let ts = typeof timestamp === 'string' ? parseInt(timestamp, 10) : timestamp;

  // 检查是否为有效数字
  if (isNaN(ts) || ts <= 0) {
    return false;
  }

  // 自动检测时间戳格式（秒或毫秒）
  // 如果时间戳大于 10000000000（2286-11-20），则认为是毫秒级时间戳
  if (ts > 10000000000) {
    ts = Math.floor(ts / 1000);
  }

  return Math.abs(now - ts) <= maxAge;
}

/**
 * 验证设备ID格式
 * @param deviceId 设备ID
 * @returns boolean 验证结果
 */
export function verifyDeviceId(deviceId: string): boolean {
  if (!deviceId || typeof deviceId !== 'string') {
    return false;
  }

  // 设备ID必须为格式：MAC_[32位十六进制]
  return /^MAC_[A-F0-9]{32}$/i.test(deviceId);
}

/**
 * 验证请求参数完整性（API Key 认证）
 * @param request 请求数据
 * @param apiKey API密钥
 * @param allowedCommands 允许的命令列表
 * @returns Promise<ValidationResult> 验证结果
 */
export async function validateRequest(
  request: CommandRequest,
  apiKey: string,
  allowedCommands?: string[]
): Promise<ValidationResult> {
  // 检查必填字段
  if (!request.device_id || !request.cmd || !request.ts || !request.api_key) {
    return {
      valid: false,
      error: 'MISSING_REQUIRED_FIELDS',
      details: { message: '缺少必填字段: device_id, cmd, ts, api_key' },
    };
  }

  // 验证API Key
  if (request.api_key !== apiKey) {
    return {
      valid: false,
      error: 'INVALID_API_KEY',
      details: { message: 'API Key验证失败' },
    };
  }

  // 验证设备ID格式
  if (!verifyDeviceId(request.device_id)) {
    return {
      valid: false,
      error: 'INVALID_DEVICE_ID',
      details: { message: '设备ID格式无效' },
    };
  }

  // 验证时间戳
  if (!verifyTimestamp(request.ts)) {
    return {
      valid: false,
      error: 'TIMESTAMP_EXPIRED',
      details: { message: '时间戳无效或已过期' },
    };
  }

  // 验证nonce格式（如果提供）
  if (request.nonce && !verifyNonce(request.nonce)) {
    return {
      valid: false,
      error: 'INVALID_NONCE',
      details: { message: 'Nonce格式无效' },
    };
  }

  if (allowedCommands && !allowedCommands.includes(request.cmd)) {
    return {
      valid: false,
      error: 'INVALID_COMMAND',
      details: { message: '命令不在允许列表中' },
    };
  }

  return {
    valid: true,
  };
}

/**
 * 验证WebSocket连接参数（API Key 认证）
 * @param deviceId 设备ID
 * @param apiKey 提供的API Key
 * @param expectedApiKey 期望的API Key
 * @param timestamp 时间戳
 * @returns ValidationResult 验证结果
 */
export function validateWebSocketConnection(
  deviceId: string,
  apiKey: string,
  expectedApiKey: string,
  timestamp: number
): ValidationResult {
  // 检查必填字段
  if (!deviceId || !apiKey || !timestamp) {
    return {
      valid: false,
      error: 'MISSING_REQUIRED_FIELDS',
      details: { message: '缺少必填字段: device_id, api_key, ts' },
    };
  }

  // 验证API Key
  if (apiKey !== expectedApiKey) {
    return {
      valid: false,
      error: 'INVALID_API_KEY',
      details: { message: 'API Key验证失败' },
    };
  }

  // 验证设备ID格式
  if (!verifyDeviceId(deviceId)) {
    return {
      valid: false,
      error: 'INVALID_DEVICE_ID',
      details: { message: '设备ID格式无效' },
    };
  }

  // 验证时间戳
  if (!verifyTimestamp(timestamp)) {
    return {
      valid: false,
      error: 'TIMESTAMP_EXPIRED',
      details: { message: '时间戳无效或已过期' },
    };
  }

  return {
    valid: true,
  };
}

/**
 * 验证nonce格式
 * @param nonce nonce字符串
 * @returns boolean 验证结果
 */
export function verifyNonce(nonce: string): boolean {
  if (!nonce || typeof nonce !== 'string') {
    return false;
  }

  // nonce长度必须在8-128字符之间，且只包含字母数字、连字符和下划线
  const noncePattern = /^[a-zA-Z0-9\-_.]{8,128}$/;
  return noncePattern.test(nonce);
}

/**
 * 生成安全的随机nonce
 * @param length nonce长度
 * @returns string 随机nonce
 */
export function generateNonce(length: number = 32): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  let result = '';

  // 使用Web Crypto API生成随机数
  const randomValues = new Uint8Array(length);
  crypto.getRandomValues(randomValues);

  for (let i = 0; i < length; i++) {
    result += chars[randomValues[i] % chars.length];
  }

  return result;
}

/**
 * 构建WebSocket连接参数（简化为 API Key 认证）
 * @param deviceId 设备ID
 * @param apiKey API密钥
 * @returns DeviceConnectionParams 连接参数
 */
export function buildConnectionParams(deviceId: string, apiKey: string): DeviceConnectionParams {
  const timestamp = Math.floor(Date.now() / 1000);

  return {
    device_id: deviceId,
    api_key: apiKey,
    ts: timestamp,
  };
}

/**
 * 创建 API Key 认证的命令请求
 * @param deviceId 设备ID
 * @param command 命令
 * @param apiKey API密钥
 * @param params 可选参数
 * @returns CommandRequest API Key认证的请求
 */
export function createApiKeyRequest(
  deviceId: string,
  command: string,
  apiKey: string,
  params?: Record<string, JsonValue>
): CommandRequest {
  const timestamp = Math.floor(Date.now() / 1000);

  return {
    device_id: deviceId,
    cmd: command,
    ts: timestamp,
    api_key: apiKey,
    params,
  };
}

/**
 * 简化的API Key请求验证（用于中间件）
 * @param request 请求数据
 * @param apiKey API密钥
 * @returns ValidationResult 验证结果
 */
export function validateApiKeyRequest(request: CommandRequest, apiKey: string): ValidationResult {
  // 快速验证主要字段
  if (!request.device_id || !request.cmd || !request.ts || !request.api_key) {
    return {
      valid: false,
      error: 'MISSING_REQUIRED_FIELDS',
      details: { message: '缺少必填字段: device_id, cmd, ts, api_key' },
    };
  }

  // 验证API Key
  if (request.api_key !== apiKey) {
    return {
      valid: false,
      error: 'INVALID_API_KEY',
      details: { message: 'API Key验证失败' },
    };
  }

  // 基础格式验证
  if (!verifyDeviceId(request.device_id)) {
    return {
      valid: false,
      error: 'INVALID_DEVICE_ID',
      details: { message: '设备ID格式无效' },
    };
  }

  if (!verifyTimestamp(request.ts)) {
    return {
      valid: false,
      error: 'TIMESTAMP_EXPIRED',
      details: { message: '时间戳无效或已过期' },
    };
  }

  return {
    valid: true,
  };
}
