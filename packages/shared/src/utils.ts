// 生成随机字符串
export function generateRandomString(length: number): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

/**
 * 恒定时间字符串比较（防时序侧信道，M9）
 *
 * 逐字符异或并 OR 累积，最终结果为 0 才相等。长度差异会提前返回，
 * 因为 tokenHash 等摘要的长度本身不是敏感信息。
 */
export function constantTimeStringEqual(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

// 生成设备ID（使用加密安全的随机数）
export function generateDeviceId(): string {
  try {
    const crypto = require('crypto');
    // 生成 16 字节（128 位）完全随机的数据
    const randomBytes = crypto.randomBytes(16);
    const randomHex = randomBytes.toString('hex');
    return `MAC_${randomHex}`.toUpperCase();
  } catch (error) {
    // 降级方案：使用多次 Math.random() 增加熵值
    const parts = [];
    for (let i = 0; i < 4; i++) {
      parts.push(Math.random().toString(36).substring(2, 10));
    }
    return `MAC_${parts.join('')}`.toUpperCase();
  }
}

// 生成密钥
export function generateSecretKey(): string {
  // 使用 Node.js crypto 模块
  try {
    const crypto = require('crypto');
    const buffer = crypto.randomBytes(32);
    return buffer.toString('hex');
  } catch {
    // 降级方案：使用随机字符串
    return generateRandomString(64);
  }
}

// 保持向后兼容的别名
export const generateSigningKey = generateSecretKey;

// 生成nonce
export function generateNonce(): string {
  return generateRandomString(16);
}

// 验证URL格式
export function isValidURL(url: string): boolean {
  try {
    const parsed = new URL(url);
    return ['http:', 'https:'].includes(parsed.protocol);
  } catch {
    return false;
  }
}

// 格式化时间
export function formatDuration(ms: number): string {
  const seconds = Math.floor(ms / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (days > 0) {
    return `${days}天${hours % 24}小时`;
  } else if (hours > 0) {
    return `${hours}小时${minutes % 60}分钟`;
  } else if (minutes > 0) {
    return `${minutes}分钟${seconds % 60}秒`;
  } else {
    return `${seconds}秒`;
  }
}

// 格式化文件大小
export function formatFileSize(bytes: number): string {
  const units = ['B', 'KB', 'MB', 'GB'];
  let size = bytes;
  let unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }

  return `${size.toFixed(1)} ${units[unitIndex]}`;
}

// 延迟执行
export function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// 重试机制
export async function retry<T>(
  fn: () => Promise<T>,
  maxAttempts: number = 3,
  delayMs: number = 1000
): Promise<T> {
  let lastError: Error;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error as Error;
      if (attempt === maxAttempts) {
        throw lastError;
      }
      await delay(delayMs * attempt); // 指数退避
    }
  }

  throw lastError!;
}

// 防抖函数
export function debounce<T extends (...args: any[]) => any>(
  func: T,
  wait: number
): (...args: Parameters<T>) => void {
  let timeout: ReturnType<typeof setTimeout>;
  return (...args: Parameters<T>) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => func(...args), wait);
  };
}

// 节流函数
export function throttle<T extends (...args: any[]) => any>(
  func: T,
  limit: number
): (...args: Parameters<T>) => void {
  let inThrottle: boolean;
  return (...args: Parameters<T>) => {
    if (!inThrottle) {
      func(...args);
      inThrottle = true;
      setTimeout(() => inThrottle = false, limit);
    }
  };
}

/**
 * 创建标准的命令执行结果对象
 * @param success 是否成功
 * @param message 消息
 * @param error 错误信息（可选）
 * @param data 附加数据（可选）
 * @returns 命令结果对象
 */
export function createCommandResult<T = unknown>(
  success: boolean,
  message: string,
  error?: string,
  data?: T
): CommandResult<T> {
  const result: CommandResult<T> = {
    success,
    message,
    timestamp: Date.now(),
  };

  if (data !== undefined) {
    result.data = data;
  }

  if (error !== undefined && !success) {
    result.error = error;

    if (data === undefined) {
      result.data = { error } as unknown as T;
    } else if (typeof data === 'object' && data !== null) {
      result.data = { ...(data as Record<string, unknown>), error } as unknown as T;
    }
  }

  return result;
}
import type { CommandResult } from './types/command.types';
