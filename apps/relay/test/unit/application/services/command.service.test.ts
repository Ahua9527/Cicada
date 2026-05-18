import { CommandService } from '@/application/services/command.service';
import type { CommandQueue } from '@/application/services/command.service';
import { Command, CommandId, CommandPriority } from '@/domain/command/command.entity';
import { CicadaError, ErrorCode, ErrorSeverity } from '@cicada/shared/errors';
import type { DeviceId } from '@cicada/shared/types/common.types';
import type { CommandType } from '@cicada/shared/types/command.types';

describe('CommandService', () => {
  let service: CommandService;
  let mockQueue: jest.Mocked<CommandQueue>;

  const DEVICE_ID = 'MAC_0123456789abcdef0123456789abcdef' as DeviceId;
  const COMMAND_ID = CommandId.create('cmd-123')!;

  beforeEach(() => {
    mockQueue = {
      enqueue: jest.fn(),
      dequeue: jest.fn(),
      find: jest.fn(),
      listPending: jest.fn(),
    } as any;

    service = new CommandService({ commandQueue: mockQueue });
  });

  describe('createCommand', () => {
    it('should create and enqueue a command', async () => {
      mockQueue.enqueue.mockResolvedValue({ success: true, data: undefined });

      const result = await service.createCommand(DEVICE_ID, 'SYSTEM_INFO' as CommandType);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBeInstanceOf(Command);
        expect(result.data.deviceId).toBe(DEVICE_ID);
      }
      expect(mockQueue.enqueue).toHaveBeenCalledTimes(1);
    });

    it('should create command with custom options', async () => {
      mockQueue.enqueue.mockResolvedValue({ success: true, data: undefined });

      const result = await service.createCommand(
        DEVICE_ID,
        'SYSTEM_INFO' as CommandType,
        undefined,
        {
          priority: CommandPriority.HIGH,
          maxRetries: 5,
          timeoutMs: 10000,
        }
      );

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.priority).toBe(CommandPriority.HIGH);
      }
    });

    it('should fail if enqueue fails', async () => {
      mockQueue.enqueue.mockResolvedValue({
        success: false,
        error: new CicadaError('Queue full', ErrorCode.SYSTEM_ERROR, {
          severity: ErrorSeverity.HIGH,
        }),
      });

      const result = await service.createCommand(DEVICE_ID, 'SYSTEM_INFO' as CommandType);

      expect(result.success).toBe(false);
    });
  });

  describe('getCommand', () => {
    it('should retrieve existing command', async () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: 'SYSTEM_INFO' as CommandType,
      });

      mockQueue.find.mockResolvedValue({ success: true, data: command });

      const result = await service.getCommand(COMMAND_ID);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBe(command);
      }
    });

    it('should return null for non-existent command', async () => {
      mockQueue.find.mockResolvedValue({ success: true, data: null });

      const result = await service.getCommand(COMMAND_ID);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBeNull();
      }
    });
  });

  describe('getNextCommand', () => {
    it('should dequeue and mark command as executing', async () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: 'SYSTEM_INFO' as CommandType,
      });
      command.markQueued();

      mockQueue.dequeue.mockResolvedValue({ success: true, data: command });

      const result = await service.getNextCommand(DEVICE_ID);

      expect(result.success).toBe(true);
      if (result.success && result.data) {
        expect(result.data.status).toBe('executing');
      }
    });

    it('should return null when queue is empty', async () => {
      mockQueue.dequeue.mockResolvedValue({ success: true, data: null });

      const result = await service.getNextCommand(DEVICE_ID);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBeNull();
      }
    });
  });

  describe('completeCommand', () => {
    it('should mark command as completed', async () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: 'SYSTEM_INFO' as CommandType,
      });
      command.markQueued();
      command.markExecuting();

      mockQueue.find.mockResolvedValue({ success: true, data: command });

      const result = await service.completeCommand(COMMAND_ID, { success: true });

      expect(result.success).toBe(true);
      expect(command.status).toBe('completed');
    });

    it('should fail for non-existent command', async () => {
      mockQueue.find.mockResolvedValue({ success: true, data: null });

      const result = await service.completeCommand(COMMAND_ID, {});

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.code).toBe(ErrorCode.COMMAND_NOT_FOUND);
      }
    });

    it('should fail for invalid state transition', async () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: 'SYSTEM_INFO' as CommandType,
      });

      mockQueue.find.mockResolvedValue({ success: true, data: command });

      const result = await service.completeCommand(COMMAND_ID, {});

      expect(result.success).toBe(false);
    });
  });

  describe('failCommand', () => {
    it('should mark command as failed', async () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: 'SYSTEM_INFO' as CommandType,
        maxRetries: 0,
      });
      command.markQueued();
      command.markExecuting();

      mockQueue.find.mockResolvedValue({ success: true, data: command });

      const result = await service.failCommand(COMMAND_ID, 'Timeout');

      expect(result.success).toBe(true);
      expect(command.status).toBe('failed');
    });

    it('should retry command if retries available', async () => {
      const command = Command.create({
        deviceId: DEVICE_ID,
        type: 'SYSTEM_INFO' as CommandType,
        maxRetries: 3,
      });
      command.markQueued();
      command.markExecuting();

      mockQueue.find.mockResolvedValue({ success: true, data: command });
      mockQueue.enqueue.mockResolvedValue({ success: true, data: undefined });

      const result = await service.failCommand(COMMAND_ID, 'Temporary error');

      expect(result.success).toBe(true);
      expect(command.retryCount).toBe(1);
      expect(mockQueue.enqueue).toHaveBeenCalled();
    });

    it('should fail for non-existent command', async () => {
      mockQueue.find.mockResolvedValue({ success: true, data: null });

      const result = await service.failCommand(COMMAND_ID, 'Error');

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.code).toBe(ErrorCode.COMMAND_NOT_FOUND);
      }
    });
  });
});
