import type { Result } from '@cicada/shared/errors';
import { ErrorCode, ErrorSeverity, CicadaError } from '@cicada/shared/errors';
import type { JsonValue, DeviceId } from '@cicada/shared/types/common.types';
import type { Device } from './device.entity';

export class DeviceRepositoryError extends CicadaError {
  constructor(message: string, context?: Record<string, JsonValue>) {
    super(message, ErrorCode.SYSTEM_ERROR, { severity: ErrorSeverity.HIGH, context });
    this.name = 'DeviceRepositoryError';
  }
}

export type DeviceResult<T> = Result<T, DeviceRepositoryError>;

export interface DeviceRepository {
  findById(deviceId: DeviceId): Promise<DeviceResult<Device | null>>;
  listConnected(): Promise<DeviceResult<Device[]>>;
  listAll(): Promise<DeviceResult<Device[]>>;
  save(device: Device): Promise<DeviceResult<void>>;
  delete(deviceId: DeviceId): Promise<DeviceResult<void>>;
}
