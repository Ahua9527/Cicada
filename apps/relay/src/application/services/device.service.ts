import type { Result } from '@cicada/shared/errors/result';
import { CicadaError, ErrorCode, ErrorSeverity } from '@cicada/shared/errors';
import type { DeviceId } from '@cicada/shared/types/common.types';
import { type DeviceInfo, type DeviceStatus } from '@cicada/shared/types/device.types';
import { Device, type DeviceMetadata } from '../../domain/device/device.entity';
import type { DeviceRepository } from '../../domain/device/device.repository';

export interface DeviceServiceDeps {
  deviceRepository: DeviceRepository;
}

export class DeviceService {
  constructor(private readonly deps: DeviceServiceDeps) {}

  async registerDevice(
    deviceId: DeviceId,
    platform: string,
    version: string,
    metadata?: DeviceMetadata
  ): Promise<Result<Device, CicadaError>> {
    try {
      // Check if device exists
      const existingResult = await this.deps.deviceRepository.findById(deviceId);
      if (!existingResult.success) {
        return { success: false, error: existingResult.error };
      }

      if (existingResult.data) {
        // Update existing device
        const device = existingResult.data;
        if (metadata) {
          device.updateMetadata(metadata);
        }
        const saveResult = await this.deps.deviceRepository.save(device);
        if (!saveResult.success) {
          return saveResult;
        }
        return { success: true, data: device };
      }

      // Create new device
      const device = Device.create({
        deviceId,
        platform,
        version,
        metadata,
      });

      const saveResult = await this.deps.deviceRepository.save(device);
      if (!saveResult.success) {
        return saveResult;
      }

      return { success: true, data: device };
    } catch (error) {
      return {
        success: false,
        error: new CicadaError('Failed to register device', ErrorCode.SYSTEM_ERROR, {
          severity: ErrorSeverity.HIGH,
          cause: error instanceof Error ? error : undefined,
        }),
      };
    }
  }

  async getDevice(deviceId: DeviceId): Promise<Result<Device | null, CicadaError>> {
    return this.deps.deviceRepository.findById(deviceId);
  }

  async updateMetadata(
    deviceId: DeviceId,
    metadata: Partial<DeviceMetadata>
  ): Promise<Result<void, CicadaError>> {
    const getResult = await this.deps.deviceRepository.findById(deviceId);
    if (!getResult.success) {
      return { success: false, error: getResult.error };
    }

    const device = getResult.data;
    if (!device) {
      return {
        success: false,
        error: new CicadaError(`Device ${deviceId} not found`, ErrorCode.DEVICE_NOT_FOUND, {
          severity: ErrorSeverity.MEDIUM,
        }),
      };
    }

    device.updateMetadata(metadata);

    const saveResult = await this.deps.deviceRepository.save(device);
    if (!saveResult.success) {
      return { success: false, error: saveResult.error };
    }

    return { success: true, data: undefined };
  }

  async connectDevice(deviceId: DeviceId, sessionId: string): Promise<Result<void, CicadaError>> {
    const getResult = await this.deps.deviceRepository.findById(deviceId);
    if (!getResult.success) {
      return { success: false, error: getResult.error };
    }

    const device = getResult.data;
    if (!device) {
      return {
        success: false,
        error: new CicadaError(`Device ${deviceId} not found`, ErrorCode.DEVICE_NOT_FOUND, {
          severity: ErrorSeverity.MEDIUM,
        }),
      };
    }

    device.markConnected(sessionId);

    const saveResult = await this.deps.deviceRepository.save(device);
    if (!saveResult.success) {
      return { success: false, error: saveResult.error };
    }

    return { success: true, data: undefined };
  }

  async disconnectDevice(deviceId: DeviceId): Promise<Result<void, CicadaError>> {
    const getResult = await this.deps.deviceRepository.findById(deviceId);
    if (!getResult.success) {
      return { success: false, error: getResult.error };
    }

    const device = getResult.data;
    if (!device) {
      return { success: true, data: undefined }; // Already disconnected
    }

    device.markDisconnected();

    const saveResult = await this.deps.deviceRepository.save(device);
    if (!saveResult.success) {
      return { success: false, error: saveResult.error };
    }

    return { success: true, data: undefined };
  }

  async recordPing(deviceId: DeviceId): Promise<Result<void, CicadaError>> {
    const getResult = await this.deps.deviceRepository.findById(deviceId);
    if (!getResult.success) {
      return { success: false, error: getResult.error };
    }

    const device = getResult.data;
    if (!device) {
      return {
        success: false,
        error: new CicadaError(`Device ${deviceId} not found`, ErrorCode.DEVICE_NOT_FOUND, {
          severity: ErrorSeverity.MEDIUM,
        }),
      };
    }

    device.recordPing();

    const saveResult = await this.deps.deviceRepository.save(device);
    if (!saveResult.success) {
      return { success: false, error: saveResult.error };
    }

    return { success: true, data: undefined };
  }

  async getDeviceInfo(deviceId: DeviceId): Promise<Result<DeviceInfo | null, CicadaError>> {
    const getResult = await this.deps.deviceRepository.findById(deviceId);
    if (!getResult.success) {
      return { success: false, error: getResult.error };
    }

    const device = getResult.data;
    if (!device) {
      return { success: true, data: null };
    }

    return { success: true, data: device.toDeviceInfo() };
  }

  async getDeviceStatus(deviceId: DeviceId): Promise<Result<DeviceStatus | null, CicadaError>> {
    const getResult = await this.deps.deviceRepository.findById(deviceId);
    if (!getResult.success) {
      return { success: false, error: getResult.error };
    }

    const device = getResult.data;
    if (!device) {
      return { success: true, data: null };
    }

    return { success: true, data: device.toDeviceStatus() };
  }
}
