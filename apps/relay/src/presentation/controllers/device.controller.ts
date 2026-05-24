/**
 * Device Controller
 * Handles device status and management
 */

import type { MiddlewareContext, DeviceListResponse, SystemStatusResponse } from '../../types';
import { API_CONSTANTS, SESSION_CONSTANTS } from '../../config/constants';

type RegistryDeviceList = {
  success?: boolean;
  devices?: NonNullable<DeviceListResponse['data']>['devices'];
  total?: number;
  active?: number;
};

type RegistryStatus = {
  success?: boolean;
  totalDevices?: number;
  activeDevices?: number;
  totalSessions?: number;
  activeConnections?: number;
};

const emptyDeviceList = (): NonNullable<DeviceListResponse['data']> => ({
  devices: [],
  total: 0,
  active: 0,
});

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
      const registryDevices = await this.getRegistryDevices(env);
      const deviceStatus =
        registryDevices.devices.find(device => device.deviceId === deviceId) ?? {
          deviceId,
          connected: false,
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
    const { env, logger, requestId } = context;

    try {
      const registryStatus = await this.getRegistryStatus(env);
      const systemStatus: SystemStatusResponse = {
        ok: true,
        data: {
          service: 'CicadaRelay',
          version: API_CONSTANTS.VERSION,
          uptime: Date.now(),
          totalDevices: registryStatus.totalDevices ?? 0,
          activeDevices: registryStatus.activeDevices ?? 0,
          totalCommands: 0,
          commandsPerSecond: 0,
          memoryUsage: 0,
          durableObjectStats: {
            totalSessions: registryStatus.totalSessions ?? 0,
            activeConnections: registryStatus.activeConnections ?? 0,
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
    const { env, logger, requestId } = context;

    try {
      const registryDevices = await this.getRegistryDevices(env);
      const deviceListResponse: DeviceListResponse = {
        ok: true,
        data: registryDevices,
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
        version: API_CONSTANTS.VERSION,
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

  private static hasRegistryBinding(env: MiddlewareContext['env']): boolean {
    return (
      typeof env.CICADA_SESSIONS?.idFromName === 'function' &&
      typeof env.CICADA_SESSIONS?.get === 'function'
    );
  }

  private static getRegistryStub(env: MiddlewareContext['env']) {
    const registryId = env.CICADA_SESSIONS.idFromName(SESSION_CONSTANTS.REGISTRY_DO_NAME);
    return env.CICADA_SESSIONS.get(registryId);
  }

  private static async getRegistryDevices(
    env: MiddlewareContext['env']
  ): Promise<NonNullable<DeviceListResponse['data']>> {
    if (!this.hasRegistryBinding(env)) {
      return emptyDeviceList();
    }

    const registry = this.getRegistryStub(env);
    const response = await registry.fetch('http://session/registry/devices', {
      method: 'GET',
    });

    if (!response.ok) {
      return emptyDeviceList();
    }

    const payload = (await response.json()) as RegistryDeviceList;
    return {
      devices: payload.devices ?? [],
      total: payload.total ?? payload.devices?.length ?? 0,
      active: payload.active ?? payload.devices?.filter(device => device.connected).length ?? 0,
    };
  }

  private static async getRegistryStatus(env: MiddlewareContext['env']): Promise<RegistryStatus> {
    if (!this.hasRegistryBinding(env)) {
      return {};
    }

    const registry = this.getRegistryStub(env);
    const response = await registry.fetch('http://session/registry/status', {
      method: 'GET',
    });

    if (!response.ok) {
      return {};
    }

    return (await response.json()) as RegistryStatus;
  }
}
