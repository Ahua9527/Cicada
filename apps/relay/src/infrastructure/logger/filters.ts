/**
 * Logger Filters
 * Provides data filtering and sanitization for logs
 */

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
    'apiKey',
    'apiSecret',
    'accessToken',
    'refreshToken',
    'privateKey',
  ];

  /**
   * Filter sensitive information from an object
   */
  static filter(obj: any): any {
    if (obj === null || obj === undefined) {
      return obj;
    }

    if (typeof obj !== 'object') {
      return obj;
    }

    if (Array.isArray(obj)) {
      return obj.map(item => this.filter(item));
    }

    const filtered: any = {};
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
  static filterByTag(logs: any[], tag: string): any[] {
    return logs.filter(entry => entry.tags && entry.tags.includes(tag));
  }

  /**
   * Filter logs by multiple tags (OR logic)
   */
  static filterByAnyTag(logs: any[], tags: string[]): any[] {
    return logs.filter(entry => entry.tags && entry.tags.some((t: string) => tags.includes(t)));
  }

  /**
   * Filter logs by multiple tags (AND logic)
   */
  static filterByAllTags(logs: any[], tags: string[]): any[] {
    return logs.filter(entry => entry.tags && tags.every((t: string) => entry.tags.includes(t)));
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
  static filterByTimeRange(logs: any[], startTime: number, endTime: number): any[] {
    return logs.filter(entry => entry.timestamp >= startTime && entry.timestamp <= endTime);
  }

  /**
   * Filter logs from last N minutes
   */
  static filterLastMinutes(logs: any[], minutes: number): any[] {
    const now = Date.now();
    const startTime = now - minutes * 60 * 1000;
    return this.filterByTimeRange(logs, startTime, now);
  }

  /**
   * Filter logs from last N hours
   */
  static filterLastHours(logs: any[], hours: number): any[] {
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
  static filterByLevel(logs: any[], level: string): any[] {
    return logs.filter(entry => entry.level === level);
  }

  /**
   * Filter logs by minimum level
   */
  static filterByMinLevel(logs: any[], minLevel: string): any[] {
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
