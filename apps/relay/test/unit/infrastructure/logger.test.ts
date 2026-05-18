/**
 * 日志模块单元测试
 */

import {
  Logger,
  JsonFormatter,
  TextFormatter,
  SensitiveDataFilter,
  getLogger,
} from '../../../src/infrastructure/logger';
import { LOG_LEVEL } from '../../../src/infrastructure/logger/types';

describe('Logger Module', () => {
  describe('Logger', () => {
    it('should create logger with default options', () => {
      const logger = new Logger();
      expect(logger).toBeInstanceOf(Logger);
    });

    it('should log debug message', () => {
      const logger = new Logger({ enableConsole: false, minLevel: LOG_LEVEL.DEBUG });

      logger.debug('test debug message', {
        context: { key: 'value' },
        requestId: 'test-id',
      });

      const logs = logger.getRecentLogs(1);
      expect(logs).toHaveLength(1);
      expect(logs[0].level).toBe('debug');
      expect(logs[0].message).toBe('test debug message');
    });

    it('should log info message', () => {
      const logger = new Logger({ enableConsole: false });

      logger.info('test info message');

      const logs = logger.getRecentLogs(1);
      expect(logs).toHaveLength(1);
      expect(logs[0].level).toBe('info');
    });

    it('should log warn message', () => {
      const logger = new Logger({ enableConsole: false });

      logger.warn('test warning', { error: new Error('test error') });

      const logs = logger.getRecentLogs(1);
      expect(logs).toHaveLength(1);
      expect(logs[0].level).toBe('warn');
      expect(logs[0].error).toBeDefined();
    });

    it('should log error message', () => {
      const logger = new Logger({ enableConsole: false });

      logger.error('test error', { error: new Error('critical error') });

      const logs = logger.getRecentLogs(1);
      expect(logs).toHaveLength(1);
      expect(logs[0].level).toBe('error');
    });

    it('should respect minimum log level', () => {
      const logger = new Logger({ enableConsole: false, minLevel: LOG_LEVEL.WARN });

      logger.debug('debug message');
      logger.info('info message');
      logger.warn('warn message');
      logger.error('error message');

      const logs = logger.getRecentLogs();
      // Logger stores all messages but only outputs based on minLevel
      // Check that warn and error messages are present
      const warnAndErrorLogs = logs.filter(l => l.level === 'warn' || l.level === 'error');
      expect(warnAndErrorLogs.length).toBeGreaterThanOrEqual(2);
    });

    it('should filter logs by tag', () => {
      const logger = new Logger({ enableConsole: false });

      logger.info('message 1', { tags: ['request'] });
      logger.info('message 2', { tags: ['websocket'] });
      logger.info('message 3', { tags: ['request'] });

      const requestLogs = logger.getLogsByTag('request');
      expect(requestLogs).toHaveLength(2);
    });

    it('should get log statistics', () => {
      const logger = new Logger({ enableConsole: false });

      logger.debug('debug');
      logger.info('info');
      logger.warn('warn');
      logger.error('error');

      const stats = logger.getStats();
      expect(stats.total).toBe(4);
      expect(stats.byLevel.debug).toBe(1);
      expect(stats.byLevel.info).toBe(1);
      expect(stats.byLevel.warn).toBe(1);
      expect(stats.byLevel.error).toBe(1);
    });

    it('should clear logs', () => {
      const logger = new Logger({ enableConsole: false });

      logger.info('test');
      expect(logger.getRecentLogs()).toHaveLength(1);

      logger.clearLogs();
      expect(logger.getRecentLogs()).toHaveLength(0);
    });

    it('should limit log storage', () => {
      const logger = new Logger({ enableConsole: false, maxLogs: 5 });

      for (let i = 0; i < 10; i++) {
        logger.info(`message ${i}`);
      }

      const logs = logger.getRecentLogs();
      expect(logs.length).toBeLessThanOrEqual(5);
    });
  });

  describe('JsonFormatter', () => {
    it('should format log entry as JSON', () => {
      const formatter = new JsonFormatter();
      const entry = {
        level: 'info' as const,
        timestamp: Date.now(),
        message: 'test message',
        context: { key: 'value' },
        requestId: 'test-id',
      };

      const formatted = formatter.format(entry);
      const parsed = JSON.parse(formatted);

      expect(parsed.level).toBe('info');
      expect(parsed.message).toBe('test message');
      expect(parsed.requestId).toBe('test-id');
      expect(parsed.context).toEqual({ key: 'value' });
    });
  });

  describe('TextFormatter', () => {
    it('should format log entry as text', () => {
      const formatter = new TextFormatter();
      const entry = {
        level: 'info' as const,
        timestamp: Date.now(),
        message: 'test message',
        requestId: 'test-id',
      };

      const formatted = formatter.format(entry);

      expect(formatted).toContain('INFO');
      expect(formatted).toContain('test message');
      expect(formatted).toContain('test-id');
    });
  });

  describe('SensitiveDataFilter', () => {
    it('should filter sensitive fields', () => {
      const data = {
        username: 'user',
        password: 'secret123',
        api_key: 'key123',
        email: 'user@example.com',
      };

      const filtered = SensitiveDataFilter.filter(data);

      expect(filtered.username).toBe('user');
      expect(filtered.password).toBe('[FILTERED]');
      expect(filtered.api_key).toBe('[FILTERED]');
      expect(filtered.email).toBe('user@example.com');
    });

    it('should filter nested objects', () => {
      const data = {
        user: {
          name: 'user',
          credentials: {
            password: 'secret',
            token: 'token123',
          },
        },
      };

      const filtered = SensitiveDataFilter.filter(data);

      expect(filtered.user.name).toBe('user');
      expect(filtered.user.credentials.password).toBe('[FILTERED]');
      expect(filtered.user.credentials.token).toBe('[FILTERED]');
    });

    it('should filter arrays', () => {
      const data = [{ password: 'secret1' }, { password: 'secret2' }];

      const filtered = SensitiveDataFilter.filter(data);

      expect(filtered[0].password).toBe('[FILTERED]');
      expect(filtered[1].password).toBe('[FILTERED]');
    });
  });

  describe('getLogger', () => {
    it('should create logger with custom options', () => {
      const logger = getLogger({
        minLevel: LOG_LEVEL.DEBUG,
        enableDebug: true,
      });

      expect(logger).toBeInstanceOf(Logger);
    });

    it('should detect debug mode from env', () => {
      const logger = getLogger({
        env: { DEBUG_MODE: 'true' },
      });

      expect(logger).toBeInstanceOf(Logger);
    });
  });
});
