export type {
  ApiResponse,
  CommandRequest,
  CommandResult,
  CommandResponse,
  CommandExecutionRecord,
  DeviceStatus,
  SystemStatusResponse,
  DeviceListResponse,
  WebSocketConnectionResponse,
  BatchCommandRequest,
  BatchCommandResponse,
  AuthChallengeRequest,
  AuthChallengeResponse,
  WebSocketMessage,
  CommandType,
} from '@cicada/shared';

export interface DeviceConnectionParams {
  device_id: string;
  api_key: string;
  ts: number;
  user_agent?: string;
}
