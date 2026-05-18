import type { JsonValue, DeviceId, Timestamp } from './common.types';

/**
 * 权威命令类型定义
 *
 * 这是系统中唯一的命令列表定义（Single Source of Truth）。
 * 所有命令验证和执行都必须基于此列表。
 *
 * 添加新命令时，必须同时：
 * 1. 在此处添加类型定义
 * 2. 更新 validators/command.validator.ts 中的 SUPPORTED_COMMANDS
 * 3. 在 Cicada 的 command-executor.ts 中实现执行逻辑
 *
 * @see packages/shared/src/validators/command.validator.ts
 * @see Cicada/src/command-executor.ts
 */
export type CommandType =
  | 'lock'           // 锁定屏幕
  | 'bt_toggle'      // 切换蓝牙状态
  | 'ping'           // 连接测试
  | 'volume_mute'    // 静音/取消静音
  | 'sleep'          // 系统休眠
  | 'sleep_displays' // 显示器休眠
  | 'caffeinate'     // 保持唤醒
  | 'decaffeinate'   // 允许休眠
  | 'status';        // 获取设备状态

export interface CommandParams {
  timeout?: number;
  priority?: 'low' | 'normal' | 'high';
  retryCount?: number;
  silent?: boolean;
  [key: string]: JsonValue | undefined;
}

export interface CommandRequest {
  device_id: DeviceId;
  cmd: CommandType | string;
  ts: Timestamp;
  api_key: string;
  params?: Record<string, JsonValue>;
  nonce?: string;
}

export interface BatchCommandRequest {
  device_ids: DeviceId[];
  cmd: CommandType | string;
  ts: Timestamp;
  api_key: string;
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

