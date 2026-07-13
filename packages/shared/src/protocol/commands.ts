export const COMMAND_PROTOCOL_VERSION = 1;

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
] as const;
