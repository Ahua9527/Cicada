/**
 * 命令常量定义
 * 
 * 这个文件提供了命令相关的常量，方便在代码中引用。
 * 所有常量都基于 types/command.types.ts 中的权威定义。
 * 
 * @see ../types/command.types.ts
 * @see ../validators/command.validator.ts
 */

import type { CommandType } from '../types/command.types';

/**
 * 权威命令列表（数组形式）
 * 
 * 用途：
 * - 遍历所有支持的命令
 * - 生成命令选项列表
 * - 文档生成
 * 
 * 注意：此列表必须与 CommandType 和 SUPPORTED_COMMANDS 保持一致
 */
export const AUTHORITATIVE_COMMANDS: readonly CommandType[] = [
  'lock',
  'bt_toggle',
  'ping',
  'volume_mute',
  'sleep',
  'sleep_displays',
  'caffeinate',
  'decaffeinate',
  'status',
  'sentry_start',
  'sentry_stop',
  'sentry_status',
  'sentry_unlock',
  'sentry_open',
] as const;

/**
 * 命令数量
 */
export const COMMAND_COUNT = AUTHORITATIVE_COMMANDS.length;

/**
 * 命令描述映射
 */
export const COMMAND_DESCRIPTIONS: Readonly<Record<CommandType, string>> = {
  lock: '锁定屏幕',
  bt_toggle: '切换蓝牙状态',
  ping: '连接测试',
  volume_mute: '静音/取消静音',
  sleep: '系统休眠',
  sleep_displays: '显示器休眠',
  caffeinate: '保持唤醒',
  decaffeinate: '允许休眠',
  status: '获取设备状态',
  sentry_start: '启动哨兵',
  sentry_stop: '停止哨兵',
  sentry_status: '获取哨兵状态',
  sentry_unlock: '解除哨兵告警',
  sentry_open: '打开哨兵窗口',
} as const;

/**
 * 命令分类
 */
export const COMMAND_CATEGORIES = {
  SYSTEM: ['lock', 'sleep', 'sleep_displays'] as const,
  POWER: ['caffeinate', 'decaffeinate'] as const,
  HARDWARE: ['bt_toggle', 'volume_mute'] as const,
  UTILITY: ['ping', 'status'] as const,
  SENTRY: ['sentry_start', 'sentry_stop', 'sentry_status', 'sentry_unlock', 'sentry_open'] as const,
} as const;

/**
 * 已弃用的命令（用于向后兼容性检查）
 */
export const DEPRECATED_COMMANDS = {
  bt_on: 'bt_toggle',
  bt_off: 'bt_toggle',
  sleep_hold: 'caffeinate',
  sleep_release: 'decaffeinate',
} as const;

/**
 * 检查命令是否有效
 * 
 * @param cmd - 要检查的命令
 * @returns 命令是否在权威列表中
 */
export function isValidCommand(cmd: string): cmd is CommandType {
  return AUTHORITATIVE_COMMANDS.includes(cmd as CommandType);
}

/**
 * 获取命令描述
 * 
 * @param cmd - 命令类型
 * @returns 命令的中文描述
 */
export function getCommandDescription(cmd: CommandType): string {
  return COMMAND_DESCRIPTIONS[cmd];
}

/**
 * 获取弃用命令的替代方案
 * 
 * @param cmd - 弃用的命令
 * @returns 替代命令，如果不是弃用命令则返回 undefined
 */
export function getDeprecatedCommandReplacement(cmd: string): CommandType | undefined {
  return DEPRECATED_COMMANDS[cmd as keyof typeof DEPRECATED_COMMANDS] as CommandType | undefined;
}
