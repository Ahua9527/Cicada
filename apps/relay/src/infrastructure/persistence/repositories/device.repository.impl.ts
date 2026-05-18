/**
 * Device Repository Implementation
 * Implements DeviceRepository using Durable Objects storage
 */

import type { DeviceRepository, DeviceResult } from '../../../domain/device/device.repository';
import { DeviceRepositoryError } from '../../../domain/device/device.repository';
import {
  Device,
  DeviceConnectionStatus,
  type DeviceMetadata,
} from '../../../domain/device/device.entity';
import type { DeviceId } from '@cicada/shared/types/common.types';
import type { DeviceType, DeviceStatus } from '@cicada/shared/types/device.types';

export class DeviceRepositoryImpl implements DeviceRepository {
  constructor(private storage: any) {}

  async findById(deviceId: DeviceId): Promise<DeviceResult<Device | null>> {
    try {
      const deviceData = await this.storage.get(`device:${deviceId}`);

      if (!deviceData) {
        return { success: true, data: null };
      }

      const device = this.toEntity(deviceData);
      return { success: true, data: device };
    } catch (error) {
      return {
        success: false,
        error: this.toRepositoryError('Failed to find device', error, { deviceId }),
      };
    }
  }

  async save(device: Device): Promise<DeviceResult<void>> {
    try {
      const persisted = this.toPersisted(device);
      await this.storage.put(`device:${device.id}`, persisted);
      return { success: true, data: undefined };
    } catch (error) {
      return {
        success: false,
        error: this.toRepositoryError('Failed to save device', error, {
          deviceId: device.id,
        }),
      };
    }
  }

  async delete(deviceId: DeviceId): Promise<DeviceResult<void>> {
    try {
      await this.storage.delete(`device:${deviceId}`);
      return { success: true, data: undefined };
    } catch (error) {
      return {
        success: false,
        error: this.toRepositoryError('Failed to delete device', error, { deviceId }),
      };
    }
  }

  async listConnected(): Promise<DeviceResult<Device[]>> {
    try {
      const allDevices = await this.storage.list({ prefix: 'device:' });
      const devices: Device[] = [];

      for (const [, deviceData] of allDevices) {
        const device = this.toEntity(deviceData);
        if (device.isConnected) {
          devices.push(device);
        }
      }

      return { success: true, data: devices };
    } catch (error) {
      return {
        success: false,
        error: this.toRepositoryError('Failed to list connected devices', error),
      };
    }
  }

  async listAll(): Promise<DeviceResult<Device[]>> {
    try {
      const allDevices = await this.storage.list({ prefix: 'device:' });
      const devices: Device[] = [];

      for (const [, deviceData] of allDevices) {
        devices.push(this.toEntity(deviceData));
      }

      return { success: true, data: devices };
    } catch (error) {
      return {
        success: false,
        error: this.toRepositoryError('Failed to list devices', error),
      };
    }
  }

  private toEntity(data: PersistedDevice): Device {
    if (!data?.deviceId) {
      throw new DeviceRepositoryError('Persisted device missing deviceId');
    }

    return Device.create({
      deviceId: data.deviceId,
      platform: data.platform,
      version: data.version,
      deviceType: data.deviceType,
      capabilities: data.capabilities as any,
      metadata: data.metadata,
      connectionStatus: data.connectionStatus,
      connectedAt: data.connectedAt ?? undefined,
      lastSeen: data.lastSeen ?? undefined,
      firstSeen: data.firstSeen ?? undefined,
      lastPing: data.lastPing ?? undefined,
      messagesExchanged: data.messagesExchanged ?? undefined,
      uptime: data.uptime ?? undefined,
      sessionId: data.sessionId ?? undefined,
    });
  }

  private toPersisted(device: Device): PersistedDevice {
    const info = device.toDeviceInfo();
    const status: DeviceStatus = device.toDeviceStatus();

    return {
      deviceId: device.id,
      platform: device.platform,
      version: device.version,
      deviceType: info.deviceType,
      capabilities: device.capabilities,
      metadata: device.metadata,
      connectionStatus: device.connectionStatus,
      connectedAt: status.connectedAt ?? null,
      lastSeen: device.lastSeen ?? null,
      firstSeen: status.connectedAt ?? device.lastSeen ?? null,
      lastPing: status.lastPing ?? null,
      messagesExchanged: status.messagesExchanged ?? 0,
      uptime: status.uptime ?? 0,
      sessionId: info.sessionId ?? null,
    };
  }

  private toRepositoryError(
    message: string,
    cause: unknown,
    context?: Record<string, unknown>
  ): DeviceRepositoryError {
    return new DeviceRepositoryError(message, {
      ...context,
      cause: cause instanceof Error ? cause.message : String(cause),
    });
  }
}

type PersistedDevice = {
  deviceId: DeviceId;
  platform: string;
  version: string;
  deviceType?: DeviceType;
  capabilities: string[];
  metadata: DeviceMetadata;
  connectionStatus: DeviceConnectionStatus;
  connectedAt?: number | null;
  lastSeen?: number | null;
  firstSeen?: number | null;
  lastPing?: number | null;
  messagesExchanged?: number;
  uptime?: number;
  sessionId?: string | null;
};
