import type { ApiResponse } from './common.types';
import type { DeviceStatus } from './device.types';

export interface SystemStatusResponse extends ApiResponse {
  data?: {
    service: string;
    version: string;
    totalDevices: number;
    activeDevices: number;
    durableObjectStats: {
      totalSessions: number;
      activeConnections: number;
    };
  };
}

export interface DeviceListResponse extends ApiResponse {
  data?: {
    devices: DeviceStatus[];
    total: number;
    active: number;
    page?: number;
    pageSize?: number;
  };
}
