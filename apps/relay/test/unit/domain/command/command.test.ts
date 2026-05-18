import { Result } from '@cicada/shared/errors';
import {
  Command,
  CommandId,
  CommandStatus,
  CommandPriority,
  CommandValidator,
  CommandValidationError,
} from '@/domain/command';
import type { CommandType } from '@cicada/shared/types/command.types';

describe('Command Aggregate', () => {
  const DEVICE_ID = 'MAC_0123456789abcdef0123456789abcdef';
  const COMMAND_TYPE: CommandType = 'lock';

  describe('CommandId', () => {
    it('creates valid command id', () => {
      const commandId = CommandId.create('CMD_0123456789abcdef0123456789abcdef');
      expect(commandId).not.toBeNull();
      expect(commandId?.toString()).toBe('CMD_0123456789abcdef0123456789abcdef');
    });

    it('rejects invalid format', () => {
      expect(CommandId.create('invalid')).toBeNull();
      expect(CommandId.create('CMD_123')).toBeNull();
    });

    it('generates unique command ids', () => {
      const id1 = CommandId.generate();
      const id2 = CommandId.generate();
      expect(id1.equals(id2)).toBe(false);
      expect(id1.toString()).toMatch(/^CMD_[0-9a-f]{32}$/);
    });
  });

  describe('Command Entity', () => {
    it('creates command with default values', () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
      });

      expect(command.deviceId).toBe(DEVICE_ID);
      expect(command.type).toBe(COMMAND_TYPE);
      expect(command.status).toBe(CommandStatus.PENDING);
      expect(command.priority).toBe(CommandPriority.NORMAL);
    });

    it('creates command with custom parameters', () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
        params: { timeout: 5000 },
        priority: CommandPriority.HIGH,
        maxRetries: 5,
      });

      expect(command.params).toEqual({ timeout: 5000 });
      expect(command.priority).toBe(CommandPriority.HIGH);
    });

    it('transitions from pending to queued', () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
      });

      expect(command.status).toBe(CommandStatus.PENDING);
      command.markQueued();
      expect(command.status).toBe(CommandStatus.QUEUED);
    });

    it('transitions from queued to executing', () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
      });

      command.markQueued();
      command.markExecuting();
      expect(command.status).toBe(CommandStatus.EXECUTING);
    });

    it('completes command with result', () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
      });

      command.markQueued();
      command.markExecuting();
      command.markCompleted({ success: true });

      expect(command.status).toBe(CommandStatus.COMPLETED);
      expect(command.result).toEqual({ success: true });
      expect(command.error).toBeNull();
    });

    it('marks command as failed with error message', () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
      });

      command.markQueued();
      command.markExecuting();
      command.markFailed('Connection timeout');

      expect(command.status).toBe(CommandStatus.FAILED);
      expect(command.error).toBe('Connection timeout');
    });

    it('detects timeout when execution time exceeds limit', () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
        timeoutMs: 1000,
      });

      const baseTime = Date.now();
      command.markQueued(baseTime);
      command.markExecuting(baseTime + 100);

      expect(command.hasTimedOut(baseTime + 500)).toBe(false);
      expect(command.hasTimedOut(baseTime + 2000)).toBe(true);
    });

    it('allows retry after failure', () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
        maxRetries: 3,
      });

      command.markQueued();
      command.markExecuting();
      command.markFailed('Error');

      expect(command.canRetry()).toBe(true);
      command.retry();
      expect(command.status).toBe(CommandStatus.PENDING);
    });

    it('prevents retry after max retries reached', () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
        maxRetries: 1,
        retryCount: 1,
      });

      command.markQueued();
      command.markExecuting();
      command.markFailed('Error');

      expect(command.canRetry()).toBe(false);
      expect(() => command.retry()).toThrow();
    });

    it('calculates execution time', () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
      });

      const baseTime = 1000;
      command.markQueued(baseTime);
      command.markExecuting(baseTime + 100);
      command.markCompleted({ success: true }, baseTime + 500);

      expect(command.getExecutionTime()).toBe(400);
    });

    it('identifies terminal states', () => {
      const pendingCmd = Command.create({ deviceId: DEVICE_ID, type: COMMAND_TYPE });
      expect(pendingCmd.isTerminal()).toBe(false);

      const completedCmd = Command.create({ deviceId: DEVICE_ID, type: COMMAND_TYPE });
      completedCmd.markQueued();
      completedCmd.markExecuting();
      completedCmd.markCompleted({ success: true });
      expect(completedCmd.isTerminal()).toBe(true);

      const failedCmd = Command.create({ deviceId: DEVICE_ID, type: COMMAND_TYPE });
      failedCmd.markQueued();
      failedCmd.markExecuting();
      failedCmd.markFailed('Error');
      expect(failedCmd.isTerminal()).toBe(true);
    });
  });

  describe('CommandValidator', () => {
    const validator = new CommandValidator();

    it('validates correct command input', () => {
      const result = validator.validate({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
        createdAt: Date.now(),
      });

      expect(Result.isOk(result)).toBe(true);
      if (result.success) {
        expect(result.data).toBeInstanceOf(Command);
      }
    });

    it('rejects empty device id', () => {
      const result = validator.validate({
        deviceId: '',
        type: COMMAND_TYPE,
      });

      expect(Result.isErr(result)).toBe(true);
      if (!result.success) {
        expect(result.error).toBeInstanceOf(CommandValidationError);
        expect(result.error.message).toContain('Device ID');
      }
    });

    it('rejects invalid command id format', () => {
      const result = validator.validate({
        commandId: 'invalid',
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
      });

      expect(Result.isErr(result)).toBe(true);
      if (!result.success) {
        expect(result.error.message).toContain('Command ID');
      }
    });

    it('rejects negative maxRetries', () => {
      const result = validator.validate({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
        maxRetries: -1,
      });

      expect(Result.isErr(result)).toBe(true);
      if (!result.success) {
        expect(result.error.message).toContain('maxRetries');
      }
    });

    it('rejects invalid timeout', () => {
      const result = validator.validate({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
        timeoutMs: 0,
      });

      expect(Result.isErr(result)).toBe(true);
      if (!result.success) {
        expect(result.error.message).toContain('timeoutMs');
      }
    });

    it('rejects invalid timestamp ordering', () => {
      const result = validator.validate({
        deviceId: DEVICE_ID,
        type: COMMAND_TYPE,
        createdAt: 1000,
        queuedAt: 500,
      });

      expect(Result.isErr(result)).toBe(true);
      if (!result.success) {
        expect(result.error.message).toContain('queuedAt');
      }
    });
  });
});
