/**
 * Security Types
 */

/**
 * Threat type enumeration
 */
export enum ThreatType {
  BRUTE_FORCE = 'brute_force',
  REPLAY_ATTACK = 'replay_attack',
  INJECTION_ATTACK = 'injection_attack',
  ABNORMAL_PATTERN = 'abnormal_pattern',
  SUSPICIOUS_IP = 'suspicious_ip',
  RATE_LIMIT_EXCEEDED = 'rate_limit_exceeded',
}

/**
 * Threat event
 */
export interface ThreatEvent {
  id: string;
  type: ThreatType;
  timestamp: number;
  severity: 'low' | 'medium' | 'high' | 'critical';
  source: {
    ip: string;
    userAgent?: string;
    deviceId?: string;
    requestId?: string;
    reputation?: number;
  };
  details: Record<string, any>;
  blocked: boolean;
  mitigations: string[];
}

/**
 * IP address information
 */
export interface IPInfo {
  address: string;
  country?: string;
  asn?: string;
  isProxy: boolean;
  isTor: boolean;
  reputation: number; // 0-100
  firstSeen: number;
  lastSeen: number;
  requestCount: number;
  threatCount: number;
}

/**
 * Security configuration
 */
export interface SecurityConfig {
  // IP whitelist/blacklist
  allowedIPs: string[];
  blockedIPs: string[];

  // Threat detection
  enableThreatDetection: boolean;
  threatThresholds: {
    failedAuthPerMinute: number;
    requestsPerMinute: number;
    suspiciousPatterns: number;
  };

  // Auto protection
  enableAutoBlock: boolean;
  autoBlockDuration: number; // milliseconds
  maxBlockDuration: number; // milliseconds

  // Monitoring and reporting
  enableSecurityLogging: boolean;
  alertThresholds: {
    threatsPerMinute: number;
    blockedRequestsPerMinute: number;
  };
}

/**
 * Security analysis result
 */
export interface SecurityAnalysis {
  safe: boolean;
  threats: ThreatEvent[];
  mitigations: string[];
}
