/**
 * Logger Filters
 * Provides data filtering and sanitization for logs
 */

import type { LogEntry } from './types';

/**
 * Sensitive data filter
 * Filters out sensitive information from log context
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
    'apiKey',
    'apiSecret',
    'accessToken',
    'refreshToken',
    'privateKey',
  ];

  /**
   * Filter sensitive information from an object
   */
  static filter<T>(obj: T): T {
    if (obj === null || obj === undefined) {
      return obj;
    }

    if (typeof obj !== 'object') {
      return obj;
    }

    if (Array.isArray(obj)) {
      return obj.map(item => this.filter(item)) as T;
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

    return filtered as T;
  }

  /**
   * Add custom sensitive field patterns
   */
  static addSensitiveField(field: string): void {
    if (!this.SENSITIVE_FIELDS.includes(field)) {
      this.SENSITIVE_FIELDS.push(field);
    }
  }

  /**
   * Get list of sensitive fields
   */
  static getSensitiveFields(): readonly string[] {
    return this.SENSITIVE_FIELDS;
  }
}

/**
 * Tag filter
 * Filters log entries by tags
 */
export class TagFilter {
  /**
   * Filter logs by tag
   */
  static filterByTag(logs: LogEntry[], tag: string): LogEntry[] {
    return logs.filter(entry => entry.tags && entry.tags.includes(tag));
  }

  /**
   * Filter logs by multiple tags (OR logic)
   */
  static filterByAnyTag(logs: LogEntry[], tags: string[]): LogEntry[] {
    return logs.filter(entry => entry.tags && entry.tags.some(tag => tags.includes(tag)));
  }

  /**
   * Filter logs by multiple tags (AND logic)
   */
  static filterByAllTags(logs: LogEntry[], tags: string[]): LogEntry[] {
    return logs.filter(entry => {
      const entryTags = entry.tags;
      return entryTags !== undefined && tags.every(tag => entryTags.includes(tag));
    });
  }
}

/**
 * Time range filter
 * Filters log entries by time range
 */
export class TimeRangeFilter {
  /**
   * Filter logs within a time range
   */
  static filterByTimeRange(logs: LogEntry[], startTime: number, endTime: number): LogEntry[] {
    return logs.filter(entry => entry.timestamp >= startTime && entry.timestamp <= endTime);
  }

  /**
   * Filter logs from last N minutes
   */
  static filterLastMinutes(logs: LogEntry[], minutes: number): LogEntry[] {
    const now = Date.now();
    const startTime = now - minutes * 60 * 1000;
    return this.filterByTimeRange(logs, startTime, now);
  }

  /**
   * Filter logs from last N hours
   */
  static filterLastHours(logs: LogEntry[], hours: number): LogEntry[] {
    const now = Date.now();
    const startTime = now - hours * 60 * 60 * 1000;
    return this.filterByTimeRange(logs, startTime, now);
  }
}

/**
 * Level filter
 * Filters log entries by level
 */
export class LevelFilter {
  /**
   * Filter logs by level
   */
  static filterByLevel(logs: LogEntry[], level: string): LogEntry[] {
    return logs.filter(entry => entry.level === level);
  }

  /**
   * Filter logs by minimum level
   */
  static filterByMinLevel(logs: LogEntry[], minLevel: string): LogEntry[] {
    const levelOrder = ['debug', 'info', 'warn', 'error'];
    const minIndex = levelOrder.indexOf(minLevel.toLowerCase());

    if (minIndex === -1) {
      return logs;
    }

    return logs.filter(entry => {
      const entryIndex = levelOrder.indexOf(entry.level.toLowerCase());
      return entryIndex >= minIndex;
    });
  }
}
