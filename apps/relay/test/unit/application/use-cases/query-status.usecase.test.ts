import { QueryStatusUseCase } from '@/application/use-cases/query-status.usecase';
import type { SessionService } from '@/application/services/session.service';
import type { DeviceService } from '@/application/services/device.service';
import { Device } from '@/domain/device/device.entity';
import { Session, DeviceId as SessionDeviceId } from '@/domain/session/session.entity';
import { CicadaError, ErrorCode, ErrorSeverity } from '@cicada/shared/errors';
import type { DeviceId } from '@cicada/shared/types/common.types';

describe('QueryStatusUseCase', () => {
  let useCase: QueryStatusUseCase;
  let mockSessionService: jest.Mocked<SessionService>;
  let mockDeviceService: jest.Mocked<DeviceService>;

  const DEVICE_ID = 'MAC_0123456789abcdef0123456789abcdef' as DeviceId;

  function createMockSession(deviceId: string = DEVICE_ID): Session {
    const did = SessionDeviceId.create(deviceId)!;
    return Session.create({
      deviceId: did,
      sessionId: 'session-123',
      connectedAt: 1000,
      lastActivity: 2000,
    });
  }

  beforeEach(() => {
    mockSessionService = {
      getActiveSessionByDevice: jest.fn(),
    } as any;

    mockDeviceService = {
      getDeviceStatus: jest.fn(),
    } as any;

    useCase = new QueryStatusUseCase({
      sessionService: mockSessionService,
      deviceService: mockDeviceService,
    });
  });

  describe('execute', () => {
    it('should return device and session status', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });
      device.markConnected('session-123');

      const session = createMockSession();
      session.recordMessage(2000);
      session.recordMessage(3000);

      mockDeviceService.getDeviceStatus.mockResolvedValue({
        success: true,
        data: device.toDeviceStatus(),
      });
      mockSessionService.getActiveSessionByDevice.mockResolvedValue({
        success: true,
        data: session,
      });

      const result = await useCase.execute({ deviceId: DEVICE_ID });

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.device.deviceId).toBe(DEVICE_ID);
        expect(result.data.device.connected).toBe(true);
        expect(result.data.session).not.toBeNull();
        expect(result.data.session?.isActive).toBe(true);
        expect(result.data.session?.messagesExchanged).toBe(2);
      }
    });

    it('should return device status without session', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      mockDeviceService.getDeviceStatus.mockResolvedValue({
        success: true,
        data: device.toDeviceStatus(),
      });
      mockSessionService.getActiveSessionByDevice.mockResolvedValue({ success: true, data: null });

      const result = await useCase.execute({ deviceId: DEVICE_ID });

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.device.deviceId).toBe(DEVICE_ID);
        expect(result.data.session).toBeNull();
      }
    });

    it('should fail if device not found', async () => {
      mockDeviceService.getDeviceStatus.mockResolvedValue({ success: true, data: null });

      const result = await useCase.execute({ deviceId: DEVICE_ID });

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.code).toBe(ErrorCode.DEVICE_NOT_FOUND);
      }
    });

    it('should handle device service errors', async () => {
      mockDeviceService.getDeviceStatus.mockResolvedValue({
        success: false,
        error: new CicadaError('DB error', ErrorCode.SYSTEM_ERROR, {
          severity: ErrorSeverity.HIGH,
        }),
      });

      const result = await useCase.execute({ deviceId: DEVICE_ID });

      expect(result.success).toBe(false);
    });

    it('should handle session service errors', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      mockDeviceService.getDeviceStatus.mockResolvedValue({
        success: true,
        data: device.toDeviceStatus(),
      });
      mockSessionService.getActiveSessionByDevice.mockResolvedValue({
        success: false,
        error: new CicadaError('DB error', ErrorCode.SYSTEM_ERROR, {
          severity: ErrorSeverity.HIGH,
        }),
      });

      const result = await useCase.execute({ deviceId: DEVICE_ID });

      expect(result.success).toBe(false);
    });
  });
});
