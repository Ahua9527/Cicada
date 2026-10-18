/**
 * Device Controller
 * Handles device status and management
 */

import type { MiddlewareContext, DeviceListResponse, SystemStatusResponse } from '../../types';
import { API_CONSTANTS, SESSION_CONSTANTS } from '../../config/constants';
import { createPublicServerErrorResponse } from '../public-error-response';

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

      return createPublicServerErrorResponse(requestId, 503);
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
          totalDevices: registryStatus.totalDevices ?? 0,
          activeDevices: registryStatus.activeDevices ?? 0,
          durableObjectStats: {
            totalSessions: registryStatus.totalSessions ?? 0,
            activeConnections: registryStatus.activeConnections ?? 0,
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

      return createPublicServerErrorResponse(requestId, 503);
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

      return createPublicServerErrorResponse(requestId, 503);
    }
  }

  /**
   * Health check
   */
  static async healthCheck(context: MiddlewareContext): Promise<Response> {
    const { env, logger, requestId } = context;

    try {
      await this.getRegistryStatus(env);
      const health = {
        ok: true,
        status: 'healthy',
        timestamp: Date.now(),
        service: 'CicadaRelay',
        version: API_CONSTANTS.VERSION,
        checks: {
          api: 'ok',
          durableObjects: 'ok',
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

      return createPublicServerErrorResponse(requestId, 503);
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
      throw new Error('Registry binding unavailable');
    }

    const registry = this.getRegistryStub(env);
    const response = await registry.fetch('http://session/registry/devices', {
      method: 'GET',
    });

    if (!response.ok) {
      throw new Error(`Registry devices request failed: ${response.status}`);
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
      throw new Error('Registry binding unavailable');
    }

    const registry = this.getRegistryStub(env);
    const response = await registry.fetch('http://session/registry/status', {
      method: 'GET',
    });

    if (!response.ok) {
      throw new Error(`Registry status request failed: ${response.status}`);
    }

    return (await response.json()) as RegistryStatus;
  }
}
