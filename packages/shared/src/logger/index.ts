import { DEFAULT_LOG_LEVEL, LOG_LEVELS } from './constants';
import type { CanonicalLogLevel, LogLevel, Logger } from './logger.interface';

const SUCCESS_COLOR = '\u001b[32m';
const RESET_COLOR = '\u001b[0m';

export function createLogger(context: string, level: LogLevel = DEFAULT_LOG_LEVEL): Logger {
  const normalizeLevel = (value: LogLevel): CanonicalLogLevel =>
    (typeof value === 'string' ? value.toUpperCase() : value) as CanonicalLogLevel;

  const currentLevel = LOG_LEVELS[normalizeLevel(level)];

  const shouldLog = (targetLevel: CanonicalLogLevel): boolean =>
    LOG_LEVELS[targetLevel] >= currentLevel;

  const formatMessage = (target: CanonicalLogLevel, message: string): string => {
    const timestamp = new Date().toISOString();
    return `[${timestamp}] [${target}] [${context}] ${message}`;
  };

  return {
    debug(message: string, ...args: unknown[]): void {
      if (shouldLog('DEBUG')) {
        console.debug(formatMessage('DEBUG', message), ...args);
      }
    },
    info(message: string, ...args: unknown[]): void {
      if (shouldLog('INFO')) {
        console.info(formatMessage('INFO', message), ...args);
      }
    },
    warn(message: string, ...args: unknown[]): void {
      if (shouldLog('WARN')) {
        console.warn(formatMessage('WARN', message), ...args);
      }
    },
    error(message: string, ...args: unknown[]): void {
      if (shouldLog('ERROR')) {
        console.error(formatMessage('ERROR', message), ...args);
      }
    },
    success(message: string, ...args: unknown[]): void {
      if (shouldLog('INFO')) {
        console.info(`${SUCCESS_COLOR}${formatMessage('SUCCESS', message)}${RESET_COLOR}`, ...args);
      }
    },
  };
}

export const logger = createLogger('Cicada');

export function setLogLevel(level: LogLevel): void {
  console.log(`Log level set to: ${typeof level === 'string' ? level.toUpperCase() : level}`);
}

export type { LogLevel, Logger };
