export const COMMAND_PROTOCOL_VERSION = 2;

export const COMMANDS = [
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
  'wake',
  'restart',
  'shutdown',
  'bt_on',
  'bt_off',
  'bt_status',
  'brightness_up',
  'brightness_down',
  'brightness_set',
  'screenshot',
  'mute',
  'unmute',
  'volume_up',
  'volume_down',
  'volume_set',
  'app_open',
  'app_close',
  'app_switch',
  'app_list',
  'daemon_exit',
] as const;

/**
 * 高风险命令：`--commands all` 不包含这些命令，必须逐个点名才授权。
 */
export const HIGH_RISK_COMMANDS = [
  'sleep',
  'sentry_stop',
  'sentry_unlock',
  'restart',
  'shutdown',
  'screenshot',
  'app_close',
  'daemon_exit',
] as const satisfies readonly (typeof COMMANDS)[number][];
