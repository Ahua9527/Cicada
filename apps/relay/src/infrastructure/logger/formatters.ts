/**
 * Logger Formatters
 * Provides different formatting strategies for log entries
 */

import type { LogEntry } from './types';

/**
 * Log formatter interface
 */
export interface LogFormatter {
  format(entry: LogEntry): string;
}

/**
 * JSON formatter - outputs structured JSON logs
 */
export class JsonFormatter implements LogFormatter {
  format(entry: LogEntry): string {
    const logData: Record<string, unknown> = {
      level: entry.level,
      timestamp: entry.timestamp,
      message: entry.message,
    };

    // Add optional fields
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
 * Plain text formatter - outputs human-readable logs
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
 * Color console formatter - outputs colored logs for debugging
 */
export class ColorConsoleFormatter implements LogFormatter {
  private static readonly COLORS = {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    dim: '\x1b[2m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    magenta: '\x1b[35m',
    cyan: '\x1b[36m',
    white: '\x1b[37m',
  };

  format(entry: LogEntry): string {
    const { level, timestamp, message, requestId, deviceId, context, tags, error } = entry;

    const time = new Date(timestamp).toISOString();
    const levelColor = this.getLevelColor(level);

    let output = `${ColorConsoleFormatter.COLORS.dim}${time}${ColorConsoleFormatter.COLORS.reset} `;
    output += `${levelColor}${level.toUpperCase()}${ColorConsoleFormatter.COLORS.reset}`;

    if (requestId) {
      output += ` ${ColorConsoleFormatter.COLORS.cyan}[${requestId}]${ColorConsoleFormatter.COLORS.reset}`;
    }
    if (deviceId) {
      output += ` ${ColorConsoleFormatter.COLORS.magenta}[${deviceId}]${ColorConsoleFormatter.COLORS.reset}`;
    }

    output += ` ${message}`;

    if (context && Object.keys(context).length > 0) {
      output += `\n  ${ColorConsoleFormatter.COLORS.dim}Context:${ColorConsoleFormatter.COLORS.reset} ${JSON.stringify(context, null, 2)}`;
    }

    if (tags && tags.length > 0) {
      output += `\n  ${ColorConsoleFormatter.COLORS.dim}Tags:${ColorConsoleFormatter.COLORS.reset} ${tags.join(', ')}`;
    }

    if (error) {
      output += `\n  ${ColorConsoleFormatter.COLORS.red}Error:${ColorConsoleFormatter.COLORS.reset} ${error.name}: ${error.message}`;
      if (error.stack) {
        output += `\n${ColorConsoleFormatter.COLORS.dim}${error.stack}${ColorConsoleFormatter.COLORS.reset}`;
      }
    }

    return output;
  }

  private getLevelColor(level: string): string {
    const normalized = level.toLowerCase();
    switch (normalized) {
      case 'debug':
      case 'trace':
        return ColorConsoleFormatter.COLORS.blue;
      case 'info':
      case 'success':
        return ColorConsoleFormatter.COLORS.green;
      case 'warn':
      case 'warning':
        return ColorConsoleFormatter.COLORS.yellow;
      case 'error':
        return ColorConsoleFormatter.COLORS.red;
      default:
        return ColorConsoleFormatter.COLORS.white;
    }
  }

  static format(entry: LogEntry): string {
    const formatter = new ColorConsoleFormatter();
    return formatter.format(entry);
  }
}
