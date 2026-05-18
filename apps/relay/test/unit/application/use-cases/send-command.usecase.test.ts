import { SendCommandUseCase } from '@/application/use-cases/send-command.usecase';
import type { SessionService } from '@/application/services/session.service';
import type { CommandService } from '@/application/services/command.service';
import type { DeviceService } from '@/application/services/device.service';
import { Device } from '@/domain/device/device.entity';
import { Session } from '@/domain/session/session.entity';
import { Command, CommandPriority } from '@/domain/command/command.entity';
import { CicadaError, ErrorCode, ErrorSeverity } from '@cicada/shared/errors';
import type { DeviceId } from '@cicada/shared/types/common.types';
import type { CommandType } from '@cicada/shared/types/command.types';

describe('SendCommandUseCase', () => {
  let useCase: SendCommandUseCase;
  let mockSessionService: jest.Mocked<SessionService>;
  let mockCommandService: jest.Mocked<CommandService>;
  let mockDeviceService: jest.Mocked<DeviceService>;

  const DEVICE_ID = 'MAC_0123456789abcdef0123456789abcdef' as DeviceId;

  beforeEach(() => {
    mockSessionService = {
      getActiveSessionByDevice: jest.fn(),
    } as any;

    mockCommandService = {
      createCommand: jest.fn(),
    } as any;

    mockDeviceService = {
      getDevice: jest.fn(),
    } as any;

    useCase = new SendCommandUseCase({
      sessionService: mockSessionService,
      commandService: mockCommandService,
      deviceService: mockDeviceService,
    });
  });

  describe('execute', () => {
    it('should successfully send command to connected device', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });
      device.markConnected('session-123');

      const session = Session.create({
        deviceId: DEVICE_ID,
        connectedAt: Date.now(),
        lastActivity: Date.now(),
      });

      const command = Command.create({
        deviceId: DEVICE_ID,
        type: 'SYSTEM_INFO' as CommandType,
      });
      command.markQueued();

      mockDeviceService.getDevice.mockResolvedValue({ success: true, data: device });
      mockSessionService.getActiveSessionByDevice.mockResolvedValue({
        success: true,
        data: session,
      });
      mockCommandService.createCommand.mockResolvedValue({ success: true, data: command });

      const result = await useCase.execute({
        deviceId: DEVICE_ID,
        commandType: 'SYSTEM_INFO' as CommandType,
      });

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.commandId).toBeDefined();
        expect(result.data.status).toBe('queued');
      }
    });

    it('should fail if device not found', async () => {
      mockDeviceService.getDevice.mockResolvedValue({ success: true, data: null });

      const result = await useCase.execute({
        deviceId: DEVICE_ID,
        commandType: 'SYSTEM_INFO' as CommandType,
      });

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.code).toBe(ErrorCode.DEVICE_NOT_FOUND);
      }
    });

    it('should fail if device is not connected', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      mockDeviceService.getDevice.mockResolvedValue({ success: true, data: device });

      const result = await useCase.execute({
        deviceId: DEVICE_ID,
        commandType: 'SYSTEM_INFO' as CommandType,
      });

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.code).toBe(ErrorCode.DEVICE_OFFLINE);
      }
    });

    it('should fail if no active session', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });
      device.markConnected('session-123');

      mockDeviceService.getDevice.mockResolvedValue({ success: true, data: device });
      mockSessionService.getActiveSessionByDevice.mockResolvedValue({ success: true, data: null });

      const result = await useCase.execute({
        deviceId: DEVICE_ID,
        commandType: 'SYSTEM_INFO' as CommandType,
      });

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.code).toBe(ErrorCode.SESSION_NOT_FOUND);
      }
    });

    it('should pass command options correctly', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });
      device.markConnected('session-123');

      const session = Session.create({
        deviceId: DEVICE_ID,
        connectedAt: Date.now(),
        lastActivity: Date.now(),
      });

      const command = Command.create({
        deviceId: DEVICE_ID,
        type: 'SYSTEM_INFO' as CommandType,
      });

      mockDeviceService.getDevice.mockResolvedValue({ success: true, data: device });
      mockSessionService.getActiveSessionByDevice.mockResolvedValue({
        success: true,
        data: session,
      });
      mockCommandService.createCommand.mockResolvedValue({ success: true, data: command });

      await useCase.execute({
        deviceId: DEVICE_ID,
        commandType: 'SYSTEM_INFO' as CommandType,
        priority: CommandPriority.HIGH,
        maxRetries: 5,
        timeoutMs: 10000,
      });

      expect(mockCommandService.createCommand).toHaveBeenCalledWith(
        DEVICE_ID,
        'SYSTEM_INFO',
        undefined,
        {
          priority: CommandPriority.HIGH,
          maxRetries: 5,
          timeoutMs: 10000,
        }
      );
    });

    it('should handle command creation failure', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });
      device.markConnected('session-123');

      const session = Session.create({
        deviceId: DEVICE_ID,
        connectedAt: Date.now(),
        lastActivity: Date.now(),
      });

      mockDeviceService.getDevice.mockResolvedValue({ success: true, data: device });
      mockSessionService.getActiveSessionByDevice.mockResolvedValue({
        success: true,
        data: session,
      });
      mockCommandService.createCommand.mockResolvedValue({
        success: false,
        error: new CicadaError('Queue full', ErrorCode.SYSTEM_ERROR, {
          severity: ErrorSeverity.HIGH,
        }),
      });

      const result = await useCase.execute({
        deviceId: DEVICE_ID,
        commandType: 'SYSTEM_INFO' as CommandType,
      });

      expect(result.success).toBe(false);
    });
  });
});
