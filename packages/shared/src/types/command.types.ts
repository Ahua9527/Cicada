import type { JsonValue, DeviceId, Timestamp } from './common.types';
import { COMMANDS } from '../protocol/commands.js';

/**
 * 权威命令类型定义
 *
 * 这是系统中唯一的命令列表定义（Single Source of Truth）。
 * 所有命令验证和执行都必须基于此列表。
 *
 * 添加新命令时，只修改 protocol/commands.ts 中的命令列表，再同步 Swift 执行层。
 *
 * @see packages/shared/src/validators/command.validator.ts
 * @see Cicada/src/command-executor.ts
 */
export type CommandType = (typeof COMMANDS)[number];

export interface CommandParams {
  timeout?: number;
  priority?: 'low' | 'normal' | 'high';
  retryCount?: number;
  silent?: boolean;
  [key: string]: JsonValue | undefined;
}

export interface CommandRequest {
  device_id: DeviceId;
  command: CommandType | string;
  request_id?: string;
  params?: Record<string, JsonValue>;
}

export interface CommandResult<T = JsonValue> {
  success: boolean;
  message: string;
  commandId?: string;
  deviceId?: DeviceId;
  command?: CommandType | string;
  timestamp: Timestamp;
  executionTime?: number;
  error?: string;
  data?: T;
}
