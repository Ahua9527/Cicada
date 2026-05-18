export type CanonicalLogLevel = 'DEBUG' | 'INFO' | 'SUCCESS' | 'WARN' | 'ERROR';
export type LogLevel = CanonicalLogLevel | Lowercase<CanonicalLogLevel>;

export interface Logger {
  debug(message: string, ...args: unknown[]): void;
  info(message: string, ...args: unknown[]): void;
  warn(message: string, ...args: unknown[]): void;
  error(message: string, ...args: unknown[]): void;
  success(message: string, ...args: unknown[]): void;
}
