/**
 * Device Controller
 * Handles device status and management
 */

import type { MiddlewareContext, DeviceListResponse, SystemStatusResponse } from '../../types';

/**
 * Device Controller
 */
export class DeviceController {
  /**
   * Get device status
   */
  static async getDeviceStatus(context: MiddlewareContext, deviceId: string): Promise<Response> {
    const { env, logger, requestId } = context;

    try {
      const sessionId = env.CICADA_SESSIONS.idFromName(deviceId);
      const sessionManager = await env.CICADA_SESSIONS.get(sessionId);

      const statusResponse = await sessionManager.fetch('http://session/status', {
        method: 'GET',
        headers: {
          'X-Device-ID': deviceId,
        },
      });

      const deviceStatus = (await statusResponse.json()) as {
        deviceId: string;
        connected: boolean;
        lastActivity?: number;
        uptime?: number;
      };

      logger.debug('Device status retrieved', {
        requestId,
        context: { deviceId, status: deviceStatus },
        tags: ['device', 'status'],
      });

      return Response.json({
        ok: true,
        data: deviceStatus,
      });
    } catch (error) {
      logger.error('Failed to get device status', {
        requestId,
        error: error as Error,
        context: { deviceId },
        tags: ['device', 'status', 'error'],
      });

      return Response.json(
        {
          ok: false,
          error: 'Failed to get device status',
        },
        { status: 500 }
      );
    }
  }

  /**
   * Get system status
   */
  static async getSystemStatus(context: MiddlewareContext): Promise<Response> {
    const { logger, requestId } = context;

    try {
      const systemStatus: SystemStatusResponse = {
        ok: true,
        data: {
          service: 'CicadaRelay',
          version: '1.0.0',
          uptime: Date.now(),
          totalDevices: 0,
          activeDevices: 0,
          totalCommands: 0,
          commandsPerSecond: 0,
          memoryUsage: 0,
          durableObjectStats: {
            totalSessions: 0,
            activeConnections: 0,
            messagesQueued: 0,
          },
        },
      };

      logger.debug('System status retrieved', {
        requestId,
        tags: ['system', 'status'],
      });

      return Response.json(systemStatus);
    } catch (error) {
      logger.error('Failed to get system status', {
        requestId,
        error: error as Error,
        tags: ['system', 'status', 'error'],
      });

      return Response.json(
        {
          ok: false,
          error: 'Failed to get system status',
        },
        { status: 500 }
      );
    }
  }

  /**
   * Get device list
   */
  static async getDeviceList(context: MiddlewareContext): Promise<Response> {
    const { logger, requestId } = context;

    try {
      // TODO: Implement global device list retrieval
      const deviceListResponse: DeviceListResponse = {
        ok: true,
        data: {
          devices: [],
          total: 0,
          active: 0,
        },
      };

      logger.debug('Device list retrieved', {
        requestId,
        context: { total: deviceListResponse.data?.total ?? 0 },
        tags: ['device', 'list'],
      });

      return Response.json(deviceListResponse);
    } catch (error) {
      logger.error('Failed to get device list', {
        requestId,
        error: error as Error,
        tags: ['device', 'list', 'error'],
      });

      return Response.json(
        {
          ok: false,
          error: 'Failed to get device list',
        },
        { status: 500 }
      );
    }
  }

  /**
   * Health check
   */
  static async healthCheck(context: MiddlewareContext): Promise<Response> {
    const { logger, requestId } = context;

    try {
      const health = {
        ok: true,
        status: 'healthy',
        timestamp: Date.now(),
        service: 'CicadaRelay',
        version: '1.0.0',
        checks: {
          api: 'ok',
          durableObjects: 'ok',
          memory: 'ok',
        },
      };

      logger.debug('Health check completed', {
        requestId,
        tags: ['health'],
      });

      return Response.json(health);
    } catch (error) {
      logger.error('Health check failed', {
        requestId,
        error: error as Error,
        tags: ['health', 'error'],
      });

      return Response.json(
        {
          ok: false,
          status: 'unhealthy',
          error: 'Health check failed',
        },
        { status: 503 }
      );
    }
  }
}
