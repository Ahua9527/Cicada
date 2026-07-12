/**
 * Worker Logger
 * Main logger implementation for Cloudflare Workers environment
 */

import type { LogLevel } from '../../types';
import { JsonFormatter, TextFormatter, ColorConsoleFormatter } from './formatters';
import type { LogFormatter } from './formatters';
import { SensitiveDataFilter } from './filters';
import {
  LOG_LEVEL,
  LEVEL_ORDER,
  normalizeLogLevel,
  type LogEntry,
  type LoggerOptions,
  type NormalizedLevel,
} from './types';
import { redactSensitiveText, sanitizeError } from '../../utils/sensitive-error';

/**
 * Logger class
 * Provides structured logging with filtering and formatting
 */
export class Logger {
  private formatter: LogFormatter;
  private minLevel: NormalizedLevel;
  private enableConsole: boolean;
  private enableDebug: boolean;
  private logs: LogEntry[] = [];
  private maxLogs: number;

  constructor(options: LoggerOptions = {}) {
    this.formatter =
      options.formatter ??
      (options.enableStructured === false ? new TextFormatter() : new JsonFormatter());
    this.minLevel = normalizeLogLevel(options.minLevel ?? LOG_LEVEL.INFO);
    this.enableConsole = options.enableConsole !== false;
    this.enableDebug = options.enableDebug !== false;
    this.maxLogs = options.maxLogs ?? 10000;
  }

  /**
   * Check if log level should be recorded
   */
  private shouldLog(level: LogLevel): boolean {
    const messageLevel = normalizeLogLevel(level);
    return LEVEL_ORDER.indexOf(messageLevel) >= LEVEL_ORDER.indexOf(this.minLevel);
  }

  /**
   * Record log entry
   */
  private log(entry: LogEntry): void {
    entry = {
      ...entry,
      message: redactSensitiveText(entry.message),
      error: entry.error ? sanitizeError(entry.error) : undefined,
    };

    // Filter sensitive information
    if (entry.context) {
      entry.context = SensitiveDataFilter.filter(entry.context);
    }

    // Add to memory logs
    this.logs.push(entry);

    // Limit log count
    if (this.logs.length > this.maxLogs) {
      this.logs = this.logs.slice(-this.maxLogs);
    }

    // Output to console
    if (this.enableConsole && this.shouldLog(entry.level)) {
      let formatted: string;

      // Use color formatter in debug mode
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
    }
  }

  /**
   * Create log entry
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
   * Log DEBUG level
   */
  debug(
    message: string,
    options?: {
      context?: Record<string, unknown>;
      requestId?: string;
      deviceId?: string;
      tags?: string[];
    }
  ): void {
    const entry = this.createLogEntry(LOG_LEVEL.DEBUG, message, options);
    this.log(entry);
  }

  /**
   * Log INFO level
   */
  info(
    message: string,
    options?: {
      context?: Record<string, unknown>;
      requestId?: string;
      deviceId?: string;
      tags?: string[];
    }
  ): void {
    const entry = this.createLogEntry(LOG_LEVEL.INFO, message, options);
    this.log(entry);
  }

  /**
   * Log WARN level
   */
  warn(
    message: string,
    options?: {
      context?: Record<string, unknown>;
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
   * Log ERROR level
   */
  error(
    message: string,
    options?: {
      context?: Record<string, unknown>;
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
   * Log SUCCESS level
   */
  success(
    message: string,
    options?: {
      context?: Record<string, unknown>;
      requestId?: string;
      deviceId?: string;
      tags?: string[];
    }
  ): void {
    const entry = this.createLogEntry('success' as LogLevel, message, options);
    this.log(entry);
  }

  /**
   * Log request start
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
   * Log request success
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
   * Log request error
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
   * Log WebSocket event
   */
  logWebSocketEvent(event: string, deviceId: string, context?: Record<string, unknown>): void {
    this.info(`WebSocket ${event}`, {
      deviceId,
      context,
      tags: ['websocket', event.toLowerCase()],
    });
  }

  /**
   * Log security event
   */
  logSecurityEvent(
    event: string,
    details: Record<string, unknown>,
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
   * Get recent logs
   */
  getRecentLogs(count: number = 100): LogEntry[] {
    return this.logs.slice(-count);
  }

  /**
   * Get logs filtered by tag
   */
  getLogsByTag(tag: string, count?: number): LogEntry[] {
    const filtered = this.logs.filter(entry => entry.tags && entry.tags.includes(tag));
    return count ? filtered.slice(-count) : filtered;
  }

  /**
   * Clear logs
   */
  clearLogs(): void {
    this.logs = [];
  }

  /**
   * Get log statistics
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
          byTag[tag] = (byTag[tag] || 0) + 1;
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
