/**
 * Security Module
 * Exports all security functionality
 */

export { ThreatDetector } from './threat-detector';
export { RateLimiter, createIPRateLimiter } from './rate-limiter';
export type { RateLimitConfig } from './rate-limiter';
export { UserAgentValidator, IPValidator, RequestPatternValidator } from './validators';
export {
  ThreatType,
  type ThreatEvent,
  type IPInfo,
  type SecurityConfig,
  type SecurityAnalysis,
} from './types';

import type { Middleware, MiddlewareContext } from '../../types';
import { ThreatDetector } from './threat-detector';
import { getLogger } from '../logger';
import type { SecurityConfig } from './types';

/**
 * Security middleware
 */
export function securityMiddleware(config: SecurityConfig): Middleware {
  const detector = new ThreatDetector(config, getLogger({ enableStructured: true }));

  return async (context: MiddlewareContext, next) => {
    const { requestId } = context;

    // Cleanup expired blocks
    detector.cleanupExpiredBlocks();

    // Analyze request security
    const securityAnalysis = await detector.analyzeRequest(context);

    if (!securityAnalysis.safe) {
      // Log security event
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

      // If block_request mitigation is present, return rejection response
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

    // Continue to next middleware
    return next();
  };
}

/**
 * Create default security config
 */
export function createDefaultSecurityConfig(): SecurityConfig {
  return {
    allowedIPs: [],
    blockedIPs: [],
    enableThreatDetection: true,
    threatThresholds: {
      failedAuthPerMinute: 5,
      requestsPerMinute: 100,
      suspiciousPatterns: 10,
    },
    enableAutoBlock: true,
    autoBlockDuration: 5 * 60 * 1000, // 5 minutes
    maxBlockDuration: 60 * 60 * 1000, // 1 hour
    enableSecurityLogging: true,
    alertThresholds: {
      threatsPerMinute: 10,
      blockedRequestsPerMinute: 20,
    },
  };
}
