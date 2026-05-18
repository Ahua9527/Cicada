import type { ApiResponse, DeviceId, JsonValue, Timestamp } from './common.types';
import type { CommandResult, CommandType } from './command.types';
import type { DeviceStatus } from './device.types';

export interface CommandResponse extends ApiResponse {
  data?: {
    command_id: string;
    device_id: DeviceId;
    status: 'sent' | 'queued' | 'failed';
    timestamp: Timestamp;
  };
}

export interface SystemStatusResponse extends ApiResponse {
  data?: {
    service: string;
    version: string;
    uptime: number;
    totalDevices: number;
    activeDevices: number;
    totalCommands: number;
    commandsPerSecond: number;
    memoryUsage: number;
    durableObjectStats: {
      totalSessions: number;
      activeConnections: number;
      messagesQueued: number;
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

export interface WebSocketConnectionResponse extends ApiResponse {
  data?: {
    connection_id: string;
    device_id: DeviceId;
    connected_at: Timestamp;
    heartbeat_interval: number;
  };
}

export interface BatchCommandResponse extends ApiResponse {
  data?: {
    batch_id: string;
    results: Array<{
      device_id: DeviceId;
      success: boolean;
      error?: string;
      timestamp: Timestamp;
    }>;
    summary: {
      total: number;
      successful: number;
      failed: number;
    };
  };
}

export interface AuthChallengeRequest {
  device_id: DeviceId;
  timestamp: Timestamp;
  api_key: string;
  challenge?: string;
}

export interface AuthChallengeResponse extends ApiResponse {
  data?: {
    challenge: string;
    expires_at: Timestamp;
    signature_algorithm: string;
  };
}

export interface CommandExecutionRecord {
  command: CommandType | string;
  result: CommandResult;
}

export interface ApiErrorPayload extends ApiResponse {
  error: string;
  code?: string;
  details?: JsonValue;
}

