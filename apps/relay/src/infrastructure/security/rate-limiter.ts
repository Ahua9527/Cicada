/**
 * Rate Limiter
 * Implements rate limiting to prevent abuse
 */

/**
 * Rate limit configuration
 */
export interface RateLimitConfig {
  maxRequests: number;
  windowMs: number;
  keyGenerator?: (request: Request) => string;
}

/**
 * Rate limit entry
 */
interface RateLimitEntry {
  count: number;
  resetTime: number;
}

/**
 * Rate limiter implementation
 */
export class RateLimiter {
  private limits = new Map<string, RateLimitEntry>();
  private config: RateLimitConfig;
  private cleanupInterval: any;

  constructor(config: RateLimitConfig) {
    this.config = config;
    this.startCleanup();
  }

  /**
   * Check if request is allowed
   */
  isAllowed(key: string): boolean {
    const now = Date.now();
    const entry = this.limits.get(key);

    // No entry yet, allow request
    if (!entry) {
      this.limits.set(key, {
        count: 1,
        resetTime: now + this.config.windowMs,
      });
      return true;
    }

    // Reset time has passed, reset counter
    if (now >= entry.resetTime) {
      this.limits.set(key, {
        count: 1,
        resetTime: now + this.config.windowMs,
      });
      return true;
    }

    // Within window, check if limit exceeded
    if (entry.count >= this.config.maxRequests) {
      return false;
    }

    // Increment counter
    entry.count++;
    return true;
  }

  /**
   * Get remaining requests for key
   */
  getRemaining(key: string): number {
    const entry = this.limits.get(key);
    if (!entry) {
      return this.config.maxRequests;
    }

    const now = Date.now();
    if (now >= entry.resetTime) {
      return this.config.maxRequests;
    }

    return Math.max(0, this.config.maxRequests - entry.count);
  }

  /**
   * Get reset time for key
   */
  getResetTime(key: string): number {
    const entry = this.limits.get(key);
    if (!entry) {
      return Date.now() + this.config.windowMs;
    }

    return entry.resetTime;
  }

  /**
   * Reset limit for key
   */
  reset(key: string): void {
    this.limits.delete(key);
  }

  /**
   * Start cleanup interval
   */
  private startCleanup(): void {
    // Cleanup expired entries every minute
    this.cleanupInterval = setInterval(() => {
      this.cleanup();
    }, 60000);
  }

  /**
   * Cleanup expired entries
   */
  private cleanup(): void {
    const now = Date.now();
    for (const [key, entry] of this.limits) {
      if (now >= entry.resetTime) {
        this.limits.delete(key);
      }
    }
  }

  /**
   * Stop cleanup interval
   */
  destroy(): void {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
    }
  }

  /**
   * Get statistics
   */
  getStats(): {
    totalKeys: number;
    averageCount: number;
  } {
    const entries = Array.from(this.limits.values());
    const totalCount = entries.reduce((sum, entry) => sum + entry.count, 0);

    return {
      totalKeys: this.limits.size,
      averageCount: entries.length > 0 ? totalCount / entries.length : 0,
    };
  }
}

/**
 * Create IP-based rate limiter
 */
export function createIPRateLimiter(maxRequests: number, windowMs: number): RateLimiter {
  return new RateLimiter({
    maxRequests,
    windowMs,
    keyGenerator: (request: Request) => {
      return (
        request.headers.get('CF-Connecting-IP') ??
        request.headers.get('X-Forwarded-For')?.split(',')[0]?.trim() ??
        request.headers.get('X-Real-IP') ??
        '0.0.0.0'
      );
    },
  });
}
