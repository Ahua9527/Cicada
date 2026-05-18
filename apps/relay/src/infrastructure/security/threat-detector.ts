/**
 * Threat Detector
 * Analyzes requests for security threats
 */

import type { MiddlewareContext } from '../../types';
import type { Logger } from '../logger';
import { UserAgentValidator } from './validators';
import type { ThreatEvent, IPInfo, SecurityConfig, SecurityAnalysis, ThreatType } from './types';
import { ThreatType as ThreatTypeEnum } from './types';

/**
 * Security monitor
 */
export class ThreatDetector {
  private ipInfo = new Map<string, IPInfo>();
  private threats: ThreatEvent[] = [];
  private blockedIPs = new Map<string, { blockedUntil: number; reason: string }>();
  private config: SecurityConfig;
  private logger: Logger;

  constructor(config: SecurityConfig, logger: Logger) {
    this.config = config;
    this.logger = logger;
  }

  /**
   * Analyze request security
   */
  async analyzeRequest(context: MiddlewareContext): Promise<SecurityAnalysis> {
    const { request } = context;
    const clientIP = this.getClientIP(request);
    const threats: ThreatEvent[] = [];
    const mitigations: string[] = [];

    // Check IP blacklist
    if (this.isIPBlocked(clientIP)) {
      const threat = this.createThreatEvent(
        ThreatTypeEnum.SUSPICIOUS_IP,
        clientIP,
        'Blocked IP attempted access',
        'high'
      );
      threats.push(threat);
      mitigations.push('block_request');
    }

    // Check IP whitelist
    if (this.config.allowedIPs.length > 0 && !this.config.allowedIPs.includes(clientIP)) {
      const threat = this.createThreatEvent(
        ThreatTypeEnum.SUSPICIOUS_IP,
        clientIP,
        'Unauthorized IP attempted access',
        'medium'
      );
      threats.push(threat);
      mitigations.push('block_request');
    }

    // Check User-Agent
    const userAgent = request.headers.get('User-Agent') ?? '';
    if (UserAgentValidator.isSuspicious(userAgent)) {
      const threat = this.createThreatEvent(
        ThreatTypeEnum.ABNORMAL_PATTERN,
        clientIP,
        'Suspicious User-Agent detected',
        'medium'
      );
      threats.push(threat);
    }

    // Check request patterns
    const patternThreats = this.analyzeRequestPattern(context);
    threats.push(...patternThreats);

    // Apply auto block
    if (this.config.enableAutoBlock) {
      this.applyAutoBlock(threats, clientIP);
    }

    // Record threat events
    if (threats.length > 0) {
      await this.recordThreats(threats);
    }

    return {
      safe: mitigations.length === 0,
      threats,
      mitigations,
    };
  }

  /**
   * Get client IP address
   */
  private getClientIP(request: Request): string {
    return (
      request.headers.get('CF-Connecting-IP') ??
      request.headers.get('X-Forwarded-For')?.split(',')[0]?.trim() ??
      request.headers.get('X-Real-IP') ??
      '0.0.0.0'
    );
  }

  /**
   * Check if IP is blocked
   */
  isIPBlocked(ip: string): boolean {
    // Check static blacklist
    if (this.config.blockedIPs.includes(ip)) {
      return true;
    }

    // Check dynamic block list
    const blockInfo = this.blockedIPs.get(ip);
    if (blockInfo && blockInfo.blockedUntil > Date.now()) {
      return true;
    }

    return false;
  }

  /**
   * Analyze request pattern
   */
  private analyzeRequestPattern(context: MiddlewareContext): ThreatEvent[] {
    const threats: ThreatEvent[] = [];
    const clientIP = this.getClientIP(context.request);
    const now = Date.now();

    // Get or create IP info
    let ipInfo = this.ipInfo.get(clientIP);
    if (!ipInfo) {
      ipInfo = {
        address: clientIP,
        isProxy: false,
        isTor: false,
        reputation: 50,
        firstSeen: now,
        lastSeen: now,
        requestCount: 0,
        threatCount: 0,
      };
      this.ipInfo.set(clientIP, ipInfo);
    }

    // Update IP info
    ipInfo.lastSeen = now;
    ipInfo.requestCount++;

    // Check request frequency
    const recentRequests = this.getRecentRequestCount(clientIP, 60000);
    if (recentRequests > this.config.threatThresholds.requestsPerMinute) {
      const threat = this.createThreatEvent(
        ThreatTypeEnum.ABNORMAL_PATTERN,
        clientIP,
        `High request frequency: ${recentRequests} requests/minute`,
        'medium'
      );
      threats.push(threat);
    }

    return threats;
  }

  /**
   * Get recent request count
   */
  private getRecentRequestCount(ip: string, _timeWindow: number): number {
    const ipInfo = this.ipInfo.get(ip);
    return ipInfo ? Math.min(ipInfo.requestCount, 10) : 0;
  }

  /**
   * Create threat event
   */
  private createThreatEvent(
    type: ThreatType,
    ip: string,
    description: string,
    severity: 'low' | 'medium' | 'high' | 'critical'
  ): ThreatEvent {
    return {
      id: this.generateThreatId(),
      type,
      timestamp: Date.now(),
      severity,
      source: {
        ip,
        reputation: this.ipInfo.get(ip)?.reputation ?? 50,
      },
      details: {
        description,
      },
      blocked: false,
      mitigations: [],
    };
  }

  /**
   * Generate threat ID
   */
  private generateThreatId(): string {
    return `threat_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Apply auto block
   */
  private applyAutoBlock(threats: ThreatEvent[], ip: string): void {
    const criticalThreats = threats.filter(t => t.severity === 'critical' || t.severity === 'high');

    if (criticalThreats.length > 0) {
      const blockDuration = Math.min(
        this.config.autoBlockDuration * criticalThreats.length,
        this.config.maxBlockDuration
      );

      this.blockIP(ip, blockDuration, `Auto-block due to ${criticalThreats[0].type}`);
    }
  }

  /**
   * Block IP address
   */
  private blockIP(ip: string, duration: number, reason: string): void {
    this.blockedIPs.set(ip, {
      blockedUntil: Date.now() + duration,
      reason,
    });

    this.logger.warn('IP auto-blocked', {
      context: {
        ip,
        duration,
        reason,
        blockedUntil: Date.now() + duration,
      },
      tags: ['security', 'auto-block'],
    });
  }

  /**
   * Record threat events
   */
  private async recordThreats(threats: ThreatEvent[]): Promise<void> {
    for (const threat of threats) {
      this.threats.push(threat);

      // Update IP threat count
      const ipInfo = this.ipInfo.get(threat.source.ip);
      if (ipInfo) {
        ipInfo.threatCount++;
        ipInfo.reputation = Math.max(0, ipInfo.reputation - 10);
      }

      // Log security event
      const severity = threat.severity === 'critical' ? 'high' : threat.severity;
      this.logger.logSecurityEvent(threat.type, threat.details, severity);
    }

    // Cleanup old threats (keep last 1000)
    if (this.threats.length > 1000) {
      this.threats = this.threats.slice(-1000);
    }
  }

  /**
   * Get security statistics
   */
  getSecurityStats(): {
    totalThreats: number;
    blockedIPs: number;
    threatsByType: Record<string, number>;
    recentThreats: ThreatEvent[];
  } {
    const threatsByType: Record<string, number> = {};

    for (const threat of this.threats) {
      threatsByType[threat.type] = (threatsByType[threat.type] || 0) + 1;
    }

    return {
      totalThreats: this.threats.length,
      blockedIPs: this.blockedIPs.size,
      threatsByType,
      recentThreats: this.threats.slice(-10),
    };
  }

  /**
   * Cleanup expired blocks
   */
  cleanupExpiredBlocks(): void {
    const now = Date.now();
    for (const [ip, blockInfo] of this.blockedIPs) {
      if (blockInfo.blockedUntil <= now) {
        this.blockedIPs.delete(ip);
        this.logger.info('IP block expired', {
          context: { ip, reason: blockInfo.reason },
          tags: ['security', 'unblock'],
        });
      }
    }
  }
}
