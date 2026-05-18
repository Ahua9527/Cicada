/**
 * Logger Module
 * Exports all logger functionality
 */

export { Logger } from './worker.logger';
export { JsonFormatter, TextFormatter, ColorConsoleFormatter } from './formatters';
export type { LogFormatter } from './formatters';
export { SensitiveDataFilter, TagFilter, TimeRangeFilter, LevelFilter } from './filters';
export {
  LOG_LEVEL,
  LEVEL_ORDER,
  normalizeLogLevel,
  type LogEntry,
  type LoggerOptions,
  type NormalizedLevel,
} from './types';

import { Logger } from './worker.logger';
import { JsonFormatter } from './formatters';
import { LOG_LEVEL, type LoggerOptions } from './types';

/**
 * Default logger instance
 */
export const defaultLogger = new Logger({
  formatter: new JsonFormatter(),
  minLevel: LOG_LEVEL.INFO,
  enableConsole: true,
});

/**
 * Get logger instance
 */
export function getLogger(options?: LoggerOptions): Logger {
  // Check if debug mode (from environment variables)
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

  // Use JSON formatter with color output in debug mode
  if (debugOptions.enableDebug) {
    debugOptions.formatter = new JsonFormatter();
  }

  return new Logger(debugOptions);
}

/**
 * Get debug logger instance
 */
export function getDebugLogger(): Logger {
  return getLogger({
    minLevel: LOG_LEVEL.DEBUG,
    enableDebug: true,
    enableConsole: true,
  });
}
