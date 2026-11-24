/**
 * 命令常量定义
 * 
 * 这个文件提供了命令相关的常量，方便在代码中引用。
 * 所有常量都基于 types/command.types.ts 中的权威定义。
 * 
 * @see ../types/command.types.ts
 * @see ../validators/command.validator.ts
 */

import type { CommandType } from '../types/command.types.js';

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
  daemon_exit: '退出远程控制服务',
} as const;
