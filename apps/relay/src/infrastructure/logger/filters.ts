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
}
