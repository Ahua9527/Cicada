/**
 * 安全工具模块
 *
 * 提供IP白名单、威胁检测、安全事件记录等功能
 */

import { MiddlewareContext, Middleware } from '../types';
import { Logger, getLogger } from './logger';

/**
 * 威胁类型枚举
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
 * 威胁事件
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
 * IP地址信息
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
 * 安全配置
 */
export interface SecurityConfig {
  // IP白名单
  allowedIPs: string[];
  blockedIPs: string[];

  // 威胁检测
  enableThreatDetection: boolean;
  threatThresholds: {
    failedAuthPerMinute: number;
    requestsPerMinute: number;
    suspiciousPatterns: number;
  };

  // 自动防护
  enableAutoBlock: boolean;
  autoBlockDuration: number; // 毫秒
  maxBlockDuration: number; // 毫秒

  // 监控和报告
  enableSecurityLogging: boolean;
  alertThresholds: {
    threatsPerMinute: number;
    blockedRequestsPerMinute: number;
  };
}

/**
 * 安全监控器
 */
export class SecurityMonitor {
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
   * 分析请求安全性
   */
  async analyzeRequest(context: MiddlewareContext): Promise<{
    safe: boolean;
    threats: ThreatEvent[];
    mitigations: string[];
  }> {
    const { request } = context;
    const clientIP = this.getClientIP(request);
    const threats: ThreatEvent[] = [];
    const mitigations: string[] = [];

    // 检查IP黑名单
    if (this.isIPBlocked(clientIP)) {
      const threat = this.createThreatEvent(
        ThreatType.SUSPICIOUS_IP,
        clientIP,
        'Blocked IP attempted access',
        'high'
      );
      threats.push(threat);
      mitigations.push('block_request');
    }

    // 检查IP白名单
    if (this.config.allowedIPs.length > 0 && !this.config.allowedIPs.includes(clientIP)) {
      const threat = this.createThreatEvent(
        ThreatType.SUSPICIOUS_IP,
        clientIP,
        'Unauthorized IP attempted access',
        'medium'
      );
      threats.push(threat);
      mitigations.push('block_request');
    }

    // 检查User-Agent
    const userAgent = request.headers.get('User-Agent') ?? '';
    if (this.isSuspiciousUserAgent(userAgent)) {
      const threat = this.createThreatEvent(
        ThreatType.ABNORMAL_PATTERN,
        clientIP,
        'Suspicious User-Agent detected',
        'medium'
      );
      threats.push(threat);
    }

    // 检查请求模式
    const patternThreats = this.analyzeRequestPattern(context);
    threats.push(...patternThreats);

    // 应用自动防护
    if (this.config.enableAutoBlock) {
      this.applyAutoBlock(threats, clientIP);
    }

    // 记录威胁事件
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
   * 获取客户端IP地址
   */
  private getClientIP(request: Request): string {
    // 优先获取Cloudflare提供的IP
    return (
      request.headers.get('CF-Connecting-IP') ??
      request.headers.get('X-Forwarded-For')?.split(',')[0]?.trim() ??
      request.headers.get('X-Real-IP') ??
      '0.0.0.0'
    );
  }

  /**
   * 检查IP是否被阻止
   */
  private isIPBlocked(ip: string): boolean {
    // 检查静态黑名单
    if (this.config.blockedIPs.includes(ip)) {
      return true;
    }

    // 检查动态阻止列表
    const blockInfo = this.blockedIPs.get(ip);
    if (blockInfo && blockInfo.blockedUntil > Date.now()) {
      return true;
    }

    return false;
  }

  /**
   * 检查可疑的User-Agent
   */
  private isSuspiciousUserAgent(userAgent: string): boolean {
    // 检查空User-Agent
    if (!userAgent || userAgent.length === 0) {
      return true;
    }

    // 检查已知的恶意User-Agent模式
    const suspiciousPatterns = [
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

    return suspiciousPatterns.some(pattern => pattern.test(userAgent));
  }

  /**
   * 分析请求模式
   */
  private analyzeRequestPattern(context: MiddlewareContext): ThreatEvent[] {
    const threats: ThreatEvent[] = [];
    const clientIP = this.getClientIP(context.request);
    const now = Date.now();

    // 获取或创建IP信息
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

    // 更新IP信息
    ipInfo.lastSeen = now;
    ipInfo.requestCount++;

    // 检查请求频率
    const recentRequests = this.getRecentRequestCount(clientIP, 60000); // 1分钟内
    if (recentRequests > this.config.threatThresholds.requestsPerMinute) {
      const threat = this.createThreatEvent(
        ThreatType.ABNORMAL_PATTERN,
        clientIP,
        `High request frequency: ${recentRequests} requests/minute`,
        'medium'
      );
      threats.push(threat);
    }

    return threats;
  }

  /**
   * 获取最近请求计数
   */
  private getRecentRequestCount(ip: string, _timeWindow: number): number {
    // 简化实现，实际应该基于时间窗口的精确计数
    const ipInfo = this.ipInfo.get(ip);
    return ipInfo ? Math.min(ipInfo.requestCount, 10) : 0; // 临时实现
  }

  /**
   * 创建威胁事件
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
   * 生成威胁ID
   */
  private generateThreatId(): string {
    return `threat_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * 应用自动阻止
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
   * 阻止IP地址
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
   * 记录威胁事件
   */
  private async recordThreats(threats: ThreatEvent[]): Promise<void> {
    for (const threat of threats) {
      this.threats.push(threat);

      // 更新IP威胁计数
      const ipInfo = this.ipInfo.get(threat.source.ip);
      if (ipInfo) {
        ipInfo.threatCount++;
        ipInfo.reputation = Math.max(0, ipInfo.reputation - 10);
      }

      // 记录安全日志
      const severity = threat.severity === 'critical' ? 'high' : threat.severity;
      this.logger.logSecurityEvent(threat.type, threat.details, severity);
    }

    // 清理旧的威胁记录（保留最近1000条）
    if (this.threats.length > 1000) {
      this.threats = this.threats.slice(-1000);
    }
  }

  /**
   * 获取安全统计
   */
  getSecurityStats(): {
    totalThreats: number;
    blockedIPs: number;
    threatsByType: Record<ThreatType, number>;
    recentThreats: ThreatEvent[];
  } {
    const threatsByType: Record<ThreatType, number> = {
      [ThreatType.BRUTE_FORCE]: 0,
      [ThreatType.REPLAY_ATTACK]: 0,
      [ThreatType.INJECTION_ATTACK]: 0,
      [ThreatType.ABNORMAL_PATTERN]: 0,
      [ThreatType.SUSPICIOUS_IP]: 0,
      [ThreatType.RATE_LIMIT_EXCEEDED]: 0,
    };

    for (const threat of this.threats) {
      threatsByType[threat.type]++;
    }

    return {
      totalThreats: this.threats.length,
      blockedIPs: this.blockedIPs.size,
      threatsByType,
      recentThreats: this.threats.slice(-10), // 最近10个威胁
    };
  }

  /**
   * 清理过期的阻止记录
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

/**
 * 安全中间件
 */
export function securityMiddleware(config: SecurityConfig): Middleware {
  const monitor = new SecurityMonitor(config, getLogger({ enableStructured: true }));

  return async (context, next) => {
    const { requestId } = context;

    // 清理过期的阻止记录
    monitor.cleanupExpiredBlocks();

    // 分析请求安全性
    const securityAnalysis = await monitor.analyzeRequest(context);

    if (!securityAnalysis.safe) {
      // 记录安全事件
      context.logger.warn('Security threats detected', {
        requestId,
        context: {
          threats: securityAnalysis.threats.map(t => ({
            type: t.type,
            severity: t.severity,
            details: t.details,
          })),
          mitigations: securityAnalysis.mitigations,
        },
        tags: ['security', 'threat'],
      });

      // 如果包含阻止请求的缓解措施，返回拒绝响应
      if (securityAnalysis.mitigations.includes('block_request')) {
        return {
          continue: false,
          response: new Response(
            JSON.stringify({
              ok: false,
              error: 'Access denied',
              error_code: 'SECURITY_BLOCKED',
              request_id: requestId,
            }),
            {
              status: 403,
              headers: { 'Content-Type': 'application/json' },
            }
          ),
        };
      }
    }

    // 继续执行下一个中间件
    return next();
  };
}

/**
 * 创建默认安全配置
 */
export function createDefaultSecurityConfig(): SecurityConfig {
  return {
    allowedIPs: [], // 空表示允许所有IP
    blockedIPs: [
      // 常见的恶意IP段可以在这里配置
    ],
    enableThreatDetection: true,
    threatThresholds: {
      failedAuthPerMinute: 5,
      requestsPerMinute: 100,
      suspiciousPatterns: 10,
    },
    enableAutoBlock: true,
    autoBlockDuration: 5 * 60 * 1000, // 5分钟
    maxBlockDuration: 60 * 60 * 1000, // 1小时
    enableSecurityLogging: true,
    alertThresholds: {
      threatsPerMinute: 10,
      blockedRequestsPerMinute: 20,
    },
  };
}
