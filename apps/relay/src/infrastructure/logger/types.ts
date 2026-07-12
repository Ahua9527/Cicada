/**
 * Logger Types
 */

import type { LogLevel } from '../../types';
import type { LogFormatter } from './formatters';

export type NormalizedLevel = 'debug' | 'info' | 'warn' | 'error';

/**
 * Log entry interface
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
 * Logger options
 */
export interface LoggerOptions {
  formatter?: LogFormatter;
  minLevel?: LogLevel;
  enableConsole?: boolean;
  enableDebug?: boolean;
  enableStructured?: boolean;
  maxLogs?: number;
  env?: LoggerEnvironment;
}

export interface LoggerEnvironment {
  DEBUG_MODE?: string;
  NODE_ENV?: string;
  LOG_LEVEL?: string;
}

/**
 * Log level constants
 */
export const LOG_LEVEL = {
  DEBUG: 'debug' as LogLevel,
  INFO: 'info' as LogLevel,
  WARN: 'warn' as LogLevel,
  ERROR: 'error' as LogLevel,
} as const;

/**
 * Level order for comparison
 */
export const LEVEL_ORDER: NormalizedLevel[] = ['debug', 'info', 'warn', 'error'];

/**
 * Normalize log level to standard format
 */
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
