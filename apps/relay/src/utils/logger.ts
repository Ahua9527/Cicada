/**
 * 结构化日志系统
 *
 * 提供统一的日志记录功能，支持不同级别和格式化输出
 */

import type { Env, LogLevel } from '../types';
import { ColorConsoleFormatter, DebugLogger } from './debug-formatters';

type NormalizedLevel = 'debug' | 'info' | 'warn' | 'error';

export const LOG_LEVEL = {
  DEBUG: 'debug' as LogLevel,
  INFO: 'info' as LogLevel,
  WARN: 'warn' as LogLevel,
  ERROR: 'error' as LogLevel,
} as const;

export const normalizeLogLevel = (level: LogLevel): NormalizedLevel => {
  const value = typeof level === 'string' ? level.toLowerCase() : level;
  switch (value) {
    case 'debug':
    case 'trace':
      return 'debug';
    case 'warn':
    case 'warning':
      return 'warn';
    case 'error':
      return 'error';
    case 'success':
    case 'info':
    default:
      return 'info';
  }
};

const LEVEL_ORDER: NormalizedLevel[] = ['debug', 'info', 'warn', 'error'];

/**
 * 日志条目接口
 */
export interface LogEntry {
  level: LogLevel;
  timestamp: number;
  message: string;
  context?: Record<string, unknown>;
  requestId?: string;
  deviceId?: string;
  error?: Error;
  tags?: string[];
}

/**
 * 日志格式化器接口
 */
export interface LogFormatter {
  format(entry: LogEntry): string;
}

/**
 * JSON格式化器
 */
export class JsonFormatter implements LogFormatter {
  format(entry: LogEntry): string {
    const logData: Record<string, unknown> = {
      level: entry.level,
      timestamp: entry.timestamp,
      message: entry.message,
    };

    // 添加可选字段
    if (entry.requestId) {
      logData.requestId = entry.requestId;
    }
    if (entry.deviceId) {
      logData.deviceId = entry.deviceId;
    }
    if (entry.context) {
      logData.context = entry.context;
    }
    if (entry.tags && entry.tags.length > 0) {
      logData.tags = entry.tags;
    }
    if (entry.error) {
      logData.error = {
        name: entry.error.name,
        message: entry.error.message,
        stack: entry.error.stack,
      };
    }

    return JSON.stringify(logData);
  }
}

/**
 * 纯文本格式化器
 */
export class TextFormatter implements LogFormatter {
  format(entry: LogEntry): string {
    const timestamp = new Date(entry.timestamp).toISOString();
    const prefix = `[${timestamp}] [${entry.level.toUpperCase()}]`;

    let message = prefix;

    if (entry.requestId) {
      message += ` [${entry.requestId}]`;
    }
    if (entry.deviceId) {
      message += ` [${entry.deviceId}]`;
    }

    message += ` ${entry.message}`;

    if (entry.context) {
      message += ` | Context: ${JSON.stringify(entry.context)}`;
    }

    if (entry.tags && entry.tags.length > 0) {
      message += ` | Tags: ${entry.tags.join(', ')}`;
    }

    if (entry.error) {
      message += ` | Error: ${entry.error.name}: ${entry.error.message}`;
      if (entry.error.stack) {
        message += `\nStack: ${entry.error.stack}`;
      }
    }

    return message;
  }
}

/**
 * 敏感信息过滤器
 */
export class SensitiveDataFilter {
  private static readonly SENSITIVE_FIELDS = [
    'api_key',
    'API_KEY',
    'password',
    'token',
    'authorization',
    'secret',
    'key',
    'nonce',
    'signature',
    'ciphertext',
    'pairing',
    'pairingCode',
    'pairing_code',
    'payload',
    'shortcut',
    'shortcutToken',
    'tokenHash',
    'grantToken',
    'cicada_sc',
  ];

  /**
   * 过滤对象中的敏感信息
   */
  static filter(obj: unknown): unknown {
    if (obj === null || obj === undefined) {
      return obj;
    }

    if (typeof obj !== 'object') {
      return obj;
    }

    if (Array.isArray(obj)) {
      return obj.map(item => this.filter(item));
    }

    const filtered: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(obj)) {
      const lowerKey = key.toLowerCase();
      const isSensitive = this.SENSITIVE_FIELDS.some(field =>
        lowerKey.includes(field.toLowerCase())
      );

      if (isSensitive) {
        filtered[key] = '[FILTERED]';
      } else if (typeof value === 'object') {
        filtered[key] = this.filter(value);
      } else {
        filtered[key] = value;
      }
    }

    return filtered;
  }
}

/**
 * 日志记录器
 */
export class Logger {
  private formatter: LogFormatter;
  private minLevel: NormalizedLevel;
  private enableConsole: boolean;
  private enableDebug: boolean;
  private logs: LogEntry[] = [];
  private maxLogs: number;

  constructor(
    options: {
      formatter?: LogFormatter;
      minLevel?: LogLevel;
      enableConsole?: boolean;
      enableDebug?: boolean;
      enableStructured?: boolean;
      maxLogs?: number;
    } = {}
  ) {
    this.formatter =
      options.formatter ??
      (options.enableStructured === false ? new TextFormatter() : new JsonFormatter());
    this.minLevel = normalizeLogLevel(options.minLevel ?? LOG_LEVEL.INFO);
    this.enableConsole = options.enableConsole !== false;
    this.enableDebug = options.enableDebug !== false;
    this.maxLogs = options.maxLogs ?? 10000;
  }

  /**
   * 检查日志级别是否应该记录
   */
  private shouldLog(level: LogLevel): boolean {
    const messageLevel = normalizeLogLevel(level);
    return LEVEL_ORDER.indexOf(messageLevel) >= LEVEL_ORDER.indexOf(this.minLevel);
  }

  /**
   * 记录日志条目
   */
  private log(entry: LogEntry): void {
    // 过滤敏感信息
    if (entry.context) {
      entry.context = SensitiveDataFilter.filter(entry.context) as Record<string, unknown>;
    }

    // 添加到内存日志
    this.logs.push(entry);

    // 限制日志数量
    if (this.logs.length > this.maxLogs) {
      this.logs = this.logs.slice(-this.maxLogs);
    }

    // 输出到控制台
    if (this.enableConsole && this.shouldLog(entry.level)) {
      let formatted: string;

      // 调试模式使用彩色格式化器
      if (this.enableDebug) {
        formatted = ColorConsoleFormatter.format(entry);
      } else {
        formatted = this.formatter.format(entry);
      }

      switch (normalizeLogLevel(entry.level)) {
        case 'debug':
          console.debug(formatted);
          break;
        case 'warn':
          console.warn(formatted);
          break;
        case 'error':
          console.error(formatted);
          break;
        case 'info':
        default:
          console.info(formatted);
          break;
      }

      // 调试模式下输出额外的详细信息
      if (this.enableDebug) {
        this.logDebugDetails(entry);
      }
    }
  }

  /**
   * 创建日志条目
   */
  private createLogEntry(
    level: LogLevel,
    message: string,
    options: {
      context?: Record<string, unknown>;
      requestId?: string;
      deviceId?: string;
      error?: Error;
      tags?: string[];
    } = {}
  ): LogEntry {
    return {
      level,
      timestamp: Date.now(),
      message,
      ...options,
    };
  }

  /**
   * 记录DEBUG级别日志
   */
  debug(
    message: string,
    options?: {
      context?: Record<string, any>;
      requestId?: string;
      deviceId?: string;
      tags?: string[];
    }
  ): void {
    const entry = this.createLogEntry(LOG_LEVEL.DEBUG, message, options);
    this.log(entry);
  }

  /**
   * 记录INFO级别日志
   */
  info(
    message: string,
    options?: {
      context?: Record<string, any>;
      requestId?: string;
      deviceId?: string;
      tags?: string[];
    }
  ): void {
    const entry = this.createLogEntry(LOG_LEVEL.INFO, message, options);
    this.log(entry);
  }

  /**
   * 记录WARN级别日志
   */
  warn(
    message: string,
    options?: {
      context?: Record<string, any>;
      requestId?: string;
      deviceId?: string;
      error?: Error;
      tags?: string[];
    }
  ): void {
    const entry = this.createLogEntry(LOG_LEVEL.WARN, message, options);
    this.log(entry);
  }

  /**
   * 记录ERROR级别日志
   */
  error(
    message: string,
    options?: {
      context?: Record<string, any>;
      requestId?: string;
      deviceId?: string;
      error?: Error;
      tags?: string[];
    }
  ): void {
    const entry = this.createLogEntry(LOG_LEVEL.ERROR, message, options);
    this.log(entry);
  }

  /**
   * 记录请求开始
   */
  logRequest(requestId: string, method: string, url: string, deviceId?: string): void {
    this.info(`Request started: ${method} ${url}`, {
      requestId,
      deviceId,
      context: { method, url },
      tags: ['request', 'start'],
    });
  }

  /**
   * 记录请求成功
   */
  logRequestSuccess(
    requestId: string,
    statusCode: number,
    duration: number,
    deviceId?: string
  ): void {
    this.info(`Request completed: ${statusCode}`, {
      requestId,
      deviceId,
      context: { statusCode, duration },
      tags: ['request', 'success'],
    });
  }

  /**
   * 记录请求错误
   */
  logRequestError(
    requestId: string,
    error: Error | string,
    statusCode?: number,
    deviceId?: string
  ): void {
    const errorMessage = error instanceof Error ? error.message : error;
    const errorObj = error instanceof Error ? error : new Error(errorMessage);

    this.error(`Request failed: ${errorMessage}`, {
      requestId,
      deviceId,
      error: errorObj,
      context: { statusCode },
      tags: ['request', 'error'],
    });
  }

  /**
   * 记录WebSocket事件
   */
  logWebSocketEvent(event: string, deviceId: string, context?: Record<string, any>): void {
    this.info(`WebSocket ${event}`, {
      deviceId,
      context,
      tags: ['websocket', event.toLowerCase()],
    });
  }

  /**
   * 记录安全事件
   */
  logSecurityEvent(
    event: string,
    details: Record<string, any>,
    severity: 'low' | 'medium' | 'high' = 'medium'
  ): void {
    const level =
      severity === 'high'
        ? LOG_LEVEL.ERROR
        : severity === 'medium'
          ? LOG_LEVEL.WARN
          : LOG_LEVEL.INFO;

    this.log(
      this.createLogEntry(level, `Security event: ${event}`, {
        context: details,
        tags: ['security', event.toLowerCase(), severity],
      })
    );
  }

  /**
   * 获取最近的日志
   */
  getRecentLogs(count: number = 100): LogEntry[] {
    return this.logs.slice(-count);
  }

  /**
   * 获取按标签过滤的日志
   */
  getLogsByTag(tag: string, count?: number): LogEntry[] {
    const filtered = this.logs.filter(entry => entry.tags && entry.tags.includes(tag));

    return count ? filtered.slice(-count) : filtered;
  }

  /**
   * 记录调试详情
   */
  private logDebugDetails(entry: LogEntry): void {
    // 请求相关调试信息
    if (entry.tags?.includes('request')) {
      DebugLogger.logRequest(entry);
    }

    // WebSocket事件调试信息
    if (entry.tags?.includes('websocket')) {
      DebugLogger.logWebSocketEvent(entry);
    }

    // 性能调试信息
    if (entry.tags?.includes('performance')) {
      DebugLogger.logPerformance(entry);
    }

    // 安全事件调试信息
    if (entry.tags?.includes('security')) {
      DebugLogger.logSecurityEvent(entry);
    }
  }

  /**
   * 清空日志
   */
  clearLogs(): void {
    this.logs = [];
  }

  /**
   * 获取日志统计
   */
  getStats(): {
    total: number;
    byLevel: Record<NormalizedLevel, number>;
    byTag: Record<string, number>;
  } {
    const byLevel: Record<NormalizedLevel, number> = {
      debug: 0,
      info: 0,
      warn: 0,
      error: 0,
    };

    const byTag: Record<string, number> = {};

    for (const entry of this.logs) {
      const normalized = normalizeLogLevel(entry.level);
      byLevel[normalized]++;

      if (entry.tags) {
        for (const tag of entry.tags) {
          byTag[tag] = (byTag[tag] ?? 0) + 1;
        }
      }
    }

    return {
      total: this.logs.length,
      byLevel,
      byTag,
    };
  }
}

// 默认日志实例
export const defaultLogger = new Logger({
  formatter: new JsonFormatter(),
  minLevel: LOG_LEVEL.INFO,
  enableConsole: true,
});

/**
 * 获取日志记录器
 */
export function getLogger(options?: {
  formatter?: LogFormatter;
  minLevel?: LogLevel;
  enableConsole?: boolean;
  enableDebug?: boolean;
  enableStructured?: boolean;
  env?: Env;
}): Logger {
  // 检查是否为调试模式（从环境变量获取，而不是 process.env）
  const isDebugMode =
    options?.env?.DEBUG_MODE === 'true' ||
    options?.env?.NODE_ENV === 'development' ||
    options?.env?.LOG_LEVEL === 'debug';

  const debugOptions = {
    ...options,
    enableDebug: options?.enableDebug ?? isDebugMode,
    minLevel: options?.minLevel ?? (isDebugMode ? LOG_LEVEL.DEBUG : LOG_LEVEL.INFO),
    enableConsole: options?.enableConsole ?? true,
    enableStructured: options?.enableStructured,
  };

  // 调试模式使用彩色格式化器
  if (debugOptions.enableDebug) {
    debugOptions.formatter = new JsonFormatter(); // 仍然使用JSON格式，但会输出彩色调试信息
  }

  return new Logger(debugOptions);
}

/**
 * 获取调试日志记录器（专门用于调试）
 */
export function getDebugLogger(): Logger {
  return getLogger({
    minLevel: LOG_LEVEL.DEBUG,
    enableDebug: true,
    enableConsole: true,
  });
}
