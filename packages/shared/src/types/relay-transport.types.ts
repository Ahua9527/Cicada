import type { DeviceId, Timestamp } from './common.types';

export const RELAY_CLOSE_CODES = {
  INVALID_SESSION_OR_ROLE: 4000,
  AGENT_REPLACED: 4001,
  AGENT_UNAVAILABLE: 4002,
  AGENT_TEMPORARILY_UNAVAILABLE: 4004,
} as const;

export type RelayCloseCode = (typeof RELAY_CLOSE_CODES)[keyof typeof RELAY_CLOSE_CODES];

export type RelayControlType =
  | 'hello'
  | 'shortcut_grant_update'
  | 'shortcut_grant_update_ack'
  | 'shortcut_command'
  | 'shortcut_result'
  | 'ping'
  | 'pong'
  | 'error';
export type RelayTransportMessageType = RelayControlType;

export interface RelayBaseMessage {
  type: RelayTransportMessageType;
  id?: string;
  from?: 'agent';
  sent_at?: Timestamp;
}

export interface RelayControlMessage extends RelayBaseMessage {
  type: RelayControlType;
  data?: Record<string, unknown>;
  error?: string;
  code?: string;
}

export type RelayTransportMessage = RelayControlMessage;

export interface ShortcutGrantRecord {
  grantId: string;
  deviceId: DeviceId;
  name: string;
  tokenHash: string;
  tokenPreview: string;
  allowedCommands: string[];
  expiresAt: Timestamp;
  revokedAt?: Timestamp;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export interface ShortcutCommandRequest {
  device_id: DeviceId;
  command: string;
  request_id?: string;
}

export interface ShortcutCommandResponse {
  ok: boolean;
  request_id: string;
  command: string;
  success?: boolean;
  message?: string;
  data?: Record<string, string>;
  code?: string;
  error?: string;
  timestamp: Timestamp;
}
