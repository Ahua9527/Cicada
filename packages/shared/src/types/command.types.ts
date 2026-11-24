import type { JsonValue, DeviceId } from './common.types';
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
 * @see apps/agent/swift/Sources/CicadaSystem/MacOSCommandGateway.swift
 */
export type CommandType = (typeof COMMANDS)[number];

export interface CommandRequest {
  device_id: DeviceId;
  command: CommandType | string;
  request_id?: string;
  params?: Record<string, JsonValue>;
}
