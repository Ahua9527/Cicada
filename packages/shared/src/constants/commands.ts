/**
 * 命令常量定义
 * 
 * 这个文件提供了命令相关的常量，方便在代码中引用。
 * 所有常量都基于 types/command.types.ts 中的权威定义。
 * 
 * @see ../types/command.types.ts
 * @see ../validators/command.validator.ts
 */

import { COMMANDS } from '../protocol/commands.js';
import type { CommandType } from '../types/command.types.js';

/**
 * 权威命令列表（数组形式）
 * 
 * 用途：
 * - 遍历所有支持的命令
 * - 生成命令选项列表
 * - 文档生成
 * 
 * 此别名保留现有 API；唯一列表位于 protocol/commands.ts。
 */
export const AUTHORITATIVE_COMMANDS = COMMANDS;

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
  wake: '唤醒显示器',
  restart: '重启系统',
  shutdown: '关机',
  bt_on: '开启蓝牙',
  bt_off: '关闭蓝牙',
  bt_status: '获取蓝牙状态',
  brightness_up: '调高亮度',
  brightness_down: '调低亮度',
  brightness_set: '设置亮度',
  screenshot: '截屏',
  mute: '静音',
  unmute: '取消静音',
  volume_up: '调高音量',
  volume_down: '调低音量',
  volume_set: '设置音量',
  app_open: '打开应用',
  app_close: '关闭应用',
  app_switch: '切换到应用',
  app_list: '列出运行中应用',
} as const;

/**
 * 命令分类
 */
export const COMMAND_CATEGORIES = {
  SYSTEM: ['lock', 'sleep', 'sleep_displays', 'wake', 'restart', 'shutdown'] as const,
  POWER: ['caffeinate', 'decaffeinate'] as const,
  HARDWARE: ['bt_toggle', 'bt_on', 'bt_off', 'bt_status', 'volume_mute', 'mute', 'unmute', 'volume_up', 'volume_down', 'volume_set', 'brightness_up', 'brightness_down', 'brightness_set'] as const,
  DISPLAY: ['screenshot'] as const,
  APP: ['app_open', 'app_close', 'app_switch', 'app_list'] as const,
  UTILITY: ['ping', 'status'] as const,
  SENTRY: ['sentry_start', 'sentry_stop', 'sentry_status', 'sentry_unlock', 'sentry_open'] as const,
} as const;

/**
 * 已弃用的命令（用于向后兼容性检查）
 */
export const DEPRECATED_COMMANDS = {
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
