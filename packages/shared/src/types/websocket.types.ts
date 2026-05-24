import type { DeviceId, JsonObject, JsonValue, Timestamp } from './common.types';

export type WebSocketMessageData = JsonValue | JsonObject;

export type WebSocketMessageType =
  | 'heartbeat'
  | 'error'
  | 'pong'
  | 'ping';

export interface BaseWebSocketMessage {
  type: WebSocketMessageType;
  id?: string;
  timestamp: Timestamp;
  ts?: Timestamp;
  data?: unknown;
}

export interface HeartbeatMessage extends BaseWebSocketMessage {
  type: 'heartbeat' | 'ping' | 'pong';
  data?: {
    deviceId: DeviceId;
    latency?: number;
    receivedTimestamp?: Timestamp;
  };
}

export interface ErrorMessage extends BaseWebSocketMessage {
  type: 'error';
  error: string;
  code?: string;
}

export type WebSocketMessage = HeartbeatMessage | ErrorMessage;

export type WSMessage = WebSocketMessage;

export class WebSocketError extends Error {
  constructor(
    message: string,
    public code?: string | number,
    public originalError?: Error
  ) {
    super(message);
    this.name = 'WebSocketError';
  }
}
