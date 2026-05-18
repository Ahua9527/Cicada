import type { CanonicalLogLevel } from './logger.interface';

export const LOG_LEVELS: Record<CanonicalLogLevel, number> = {
  DEBUG: 0,
  INFO: 1,
  SUCCESS: 1.5,
  WARN: 2,
  ERROR: 3,
};

export const DEFAULT_LOG_LEVEL: CanonicalLogLevel = 'INFO';
