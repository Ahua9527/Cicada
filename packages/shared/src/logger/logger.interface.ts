export type CanonicalLogLevel = 'DEBUG' | 'INFO' | 'SUCCESS' | 'WARN' | 'ERROR';
export type LogLevel = CanonicalLogLevel | Lowercase<CanonicalLogLevel>;
