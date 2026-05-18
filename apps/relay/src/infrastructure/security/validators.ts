/**
 * Security Validators
 * Validates User-Agent, IP patterns, and other security-related inputs
 */

/**
 * User-Agent validator
 */
export class UserAgentValidator {
  private static readonly SUSPICIOUS_PATTERNS = [
    /bot/i,
    /crawler/i,
    /scanner/i,
    /curl/i,
    /wget/i,
    /python/i,
    /java/i,
    /perl/i,
    /php/i,
    /bash/i,
    /powershell/i,
  ];

  /**
   * Check if User-Agent is suspicious
   */
  static isSuspicious(userAgent: string): boolean {
    // Check empty User-Agent
    if (!userAgent || userAgent.length === 0) {
      return true;
    }

    // Check known malicious User-Agent patterns
    return this.SUSPICIOUS_PATTERNS.some(pattern => pattern.test(userAgent));
  }

  /**
   * Validate User-Agent format
   */
  static isValid(userAgent: string): boolean {
    if (!userAgent) {
      return false;
    }

    // Basic validation: should have reasonable length
    if (userAgent.length < 10 || userAgent.length > 1000) {
      return false;
    }

    return true;
  }

  /**
   * Extract browser info from User-Agent
   */
  static extractBrowserInfo(userAgent: string): {
    browser?: string;
    version?: string;
    os?: string;
  } {
    const info: { browser?: string; version?: string; os?: string } = {};

    // Extract browser
    if (/Chrome/i.test(userAgent)) {
      info.browser = 'Chrome';
    } else if (/Firefox/i.test(userAgent)) {
      info.browser = 'Firefox';
    } else if (/Safari/i.test(userAgent)) {
      info.browser = 'Safari';
    } else if (/Edge/i.test(userAgent)) {
      info.browser = 'Edge';
    }

    // Extract OS
    if (/Windows/i.test(userAgent)) {
      info.os = 'Windows';
    } else if (/Mac/i.test(userAgent)) {
      info.os = 'macOS';
    } else if (/Linux/i.test(userAgent)) {
      info.os = 'Linux';
    } else if (/Android/i.test(userAgent)) {
      info.os = 'Android';
    } else if (/iOS|iPhone|iPad/i.test(userAgent)) {
      info.os = 'iOS';
    }

    return info;
  }
}

/**
 * IP validator
 */
export class IPValidator {
  /**
   * Validate IPv4 address format
   */
  static isValidIPv4(ip: string): boolean {
    const ipv4Pattern = /^(\d{1,3}\.){3}\d{1,3}$/;
    if (!ipv4Pattern.test(ip)) {
      return false;
    }

    const parts = ip.split('.');
    return parts.every(part => {
      const num = parseInt(part, 10);
      return num >= 0 && num <= 255;
    });
  }

  /**
   * Validate IPv6 address format
   */
  static isValidIPv6(ip: string): boolean {
    const ipv6Pattern = /^([0-9a-fA-F]{0,4}:){7}[0-9a-fA-F]{0,4}$/;
    return ipv6Pattern.test(ip);
  }

  /**
   * Check if IP is private
   */
  static isPrivateIP(ip: string): boolean {
    if (!this.isValidIPv4(ip)) {
      return false;
    }

    const parts = ip.split('.').map(Number);
    const first = parts[0];
    const second = parts[1];

    // Check private IP ranges
    if (first === 10) {
      return true; // 10.0.0.0/8
    }
    if (first === 172 && second >= 16 && second <= 31) {
      return true; // 172.16.0.0/12
    }
    if (first === 192 && second === 168) {
      return true; // 192.168.0.0/16
    }
    if (first === 127) {
      return true; // 127.0.0.0/8 (loopback)
    }

    return false;
  }

  /**
   * Check if IP is in range
   */
  static isInRange(ip: string, cidr: string): boolean {
    if (!this.isValidIPv4(ip)) {
      return false;
    }

    const [range, bits] = cidr.split('/');
    if (!bits) {
      return ip === range;
    }

    const mask = ~(2 ** (32 - parseInt(bits, 10)) - 1);
    const ipNum = this.ipToNumber(ip);
    const rangeNum = this.ipToNumber(range);

    return (ipNum & mask) === (rangeNum & mask);
  }

  /**
   * Convert IP to number
   */
  private static ipToNumber(ip: string): number {
    return ip.split('.').reduce((acc, octet) => (acc << 8) + parseInt(octet, 10), 0);
  }
}

/**
 * Request pattern validator
 */
export class RequestPatternValidator {
  /**
   * Check for SQL injection patterns
   */
  static hasSQLInjectionPattern(input: string): boolean {
    const sqlPatterns = [
      /(\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|EXEC|EXECUTE)\b)/gi,
      /(\bUNION\b.*\bSELECT\b)/gi,
      /(\bOR\b\s+\d+=\d+)/gi,
      /(--|;|\/\*|\*\/)/g,
    ];

    return sqlPatterns.some(pattern => pattern.test(input));
  }

  /**
   * Check for XSS patterns
   */
  static hasXSSPattern(input: string): boolean {
    const xssPatterns = [
      /<script[^>]*>.*?<\/script>/gi,
      /javascript:/gi,
      /on\w+\s*=/gi,
      /<iframe[^>]*>/gi,
    ];

    return xssPatterns.some(pattern => pattern.test(input));
  }

  /**
   * Check for path traversal patterns
   */
  static hasPathTraversalPattern(input: string): boolean {
    const traversalPatterns = [/\.\.[/\\]/g, /%2e%2e[/\\]/gi, /\.\.%2f/gi, /\.\.%5c/gi];

    return traversalPatterns.some(pattern => pattern.test(input));
  }

  /**
   * Validate input for security
   */
  static validateInput(input: string): {
    valid: boolean;
    threats: string[];
  } {
    const threats: string[] = [];

    if (this.hasSQLInjectionPattern(input)) {
      threats.push('SQL Injection');
    }
    if (this.hasXSSPattern(input)) {
      threats.push('XSS');
    }
    if (this.hasPathTraversalPattern(input)) {
      threats.push('Path Traversal');
    }

    return {
      valid: threats.length === 0,
      threats,
    };
  }
}
