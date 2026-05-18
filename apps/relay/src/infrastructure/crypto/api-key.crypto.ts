/**
 * API Key 认证相关函数
 */

import type { CommandRequest, ValidationResult, DeviceConnectionParams } from '@/types';
import { verifyDeviceId, verifyTimestamp, verifyNonce } from './validators.crypto';

/**
 * 验证请求参数完整性（完整的 API Key 认证）
 * @param request 请求数据
 * @param apiKey API密钥
 * @param allowedCommands 允许的命令列表
 * @returns Promise<ValidationResult> 验证结果
 */
export async function validateRequest(
  request: CommandRequest,
  apiKey: string,
  _allowedCommands?: string[]
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

  // 注意：命令验证已移至 Shared 包的 CommandValidator
  // 不再在此处验证命令，由调用方使用 validateCommandRequest() 进行完整验证

  return {
    valid: true,
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
 * 构建WebSocket连接参数（API Key 认证）
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
  params?: Record<string, any>
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
