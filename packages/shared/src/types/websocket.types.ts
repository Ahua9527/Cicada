import type { CommandType } from './command.types';
import type { DeviceId, JsonObject, JsonValue, Timestamp } from './common.types';

export type WebSocketMessageData = JsonValue | JsonObject;

export type WebSocketMessageType =
  | 'command'
  | 'response'
  | 'heartbeat'
  | 'error'
  | 'pong'
  | 'ping';

export interface WebSocketMessage {
  type: WebSocketMessageType;
  id: string;
  cmd: string;
  ts: Timestamp;
  timestamp: Timestamp;
  data?: WebSocketMessageData;
  api_key?: string;
}

export interface CommandMessage extends WebSocketMessage {
  type: 'command';
  data: {
    command: CommandType;
    parameters?: JsonValue;
    signature: string;
    nonce: string;
  };
}

export interface ResponseMessage extends WebSocketMessage {
  type: 'response';
  data: {
    commandId: string;
    result: JsonValue;
  };
}

export interface HeartbeatMessage extends WebSocketMessage {
  type: 'heartbeat' | 'ping' | 'pong';
  data?: {
    deviceId: DeviceId;
    latency?: number;
  };
}

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

