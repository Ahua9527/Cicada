import { ManageSessionUseCase } from '@/application/use-cases/manage-session.usecase';
import type { SessionService } from '@/application/services/session.service';
import type { DeviceService } from '@/application/services/device.service';
import { Device } from '@/domain/device/device.entity';
import { Session, DeviceId as SessionDeviceId } from '@/domain/session/session.entity';
import { CicadaError, ErrorCode, ErrorSeverity } from '@cicada/shared/errors';
import type { DeviceId, SessionId } from '@cicada/shared/types/common.types';

describe('ManageSessionUseCase', () => {
  let useCase: ManageSessionUseCase;
  let mockSessionService: jest.Mocked<SessionService>;
  let mockDeviceService: jest.Mocked<DeviceService>;

  const DEVICE_ID = 'MAC_0123456789abcdef0123456789abcdef' as DeviceId;
  const SESSION_ID = 'session-123' as SessionId;

  function createMockSession(deviceId: string = DEVICE_ID): Session {
    const did = SessionDeviceId.create(deviceId)!;
    const session = Session.create({
      deviceId: did,
      sessionId: SESSION_ID,
      connectedAt: Date.now(),
      lastActivity: Date.now(),
    });
    return session;
  }

  beforeEach(() => {
    mockSessionService = {
      createSession: jest.fn(),
      getSession: jest.fn(),
      closeSession: jest.fn(),
      updateActivity: jest.fn(),
      recordMessage: jest.fn(),
      cleanupExpiredSessions: jest.fn(),
    } as any;

    mockDeviceService = {
      registerDevice: jest.fn(),
      connectDevice: jest.fn(),
      disconnectDevice: jest.fn(),
    } as any;

    useCase = new ManageSessionUseCase({
      sessionService: mockSessionService,
      deviceService: mockDeviceService,
    });
  });

  describe('createSession', () => {
    it('should create session and connect device', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      const session = createMockSession();

      mockDeviceService.registerDevice.mockResolvedValue({ success: true, data: device });
      mockSessionService.createSession.mockResolvedValue({ success: true, data: session });
      mockDeviceService.connectDevice.mockResolvedValue({ success: true, data: undefined });

      const result = await useCase.createSession({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.deviceId).toBe(DEVICE_ID);
        expect(result.data.sessionId).toBeDefined();
      }
      expect(mockDeviceService.connectDevice).toHaveBeenCalled();
    });

    it('should rollback session if device connection fails', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      const session = createMockSession();

      mockDeviceService.registerDevice.mockResolvedValue({ success: true, data: device });
      mockSessionService.createSession.mockResolvedValue({ success: true, data: session });
      mockDeviceService.connectDevice.mockResolvedValue({
        success: false,
        error: new CicadaError('Connection failed', ErrorCode.SYSTEM_ERROR, {
          severity: ErrorSeverity.HIGH,
        }),
      });
      mockSessionService.closeSession.mockResolvedValue({ success: true, data: undefined });

      const result = await useCase.createSession({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      expect(result.success).toBe(false);
      expect(mockSessionService.closeSession).toHaveBeenCalledWith(session.id);
    });

    it('should handle device registration failure', async () => {
      mockDeviceService.registerDevice.mockResolvedValue({
        success: false,
        error: new CicadaError('Registration failed', ErrorCode.SYSTEM_ERROR, {
          severity: ErrorSeverity.HIGH,
        }),
      });

      const result = await useCase.createSession({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      expect(result.success).toBe(false);
      expect(mockSessionService.createSession).not.toHaveBeenCalled();
    });

    it('should handle session creation failure', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      mockDeviceService.registerDevice.mockResolvedValue({ success: true, data: device });
      mockSessionService.createSession.mockResolvedValue({
        success: false,
        error: new CicadaError('Session exists', ErrorCode.SESSION_CONFLICT, {
          severity: ErrorSeverity.MEDIUM,
        }),
      });

      const result = await useCase.createSession({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      expect(result.success).toBe(false);
      expect(mockDeviceService.connectDevice).not.toHaveBeenCalled();
    });
  });

  describe('closeSession', () => {
    it('should close session and disconnect device', async () => {
      const session = createMockSession();

      mockSessionService.getSession.mockResolvedValue({ success: true, data: session });
      mockSessionService.closeSession.mockResolvedValue({ success: true, data: undefined });
      mockDeviceService.disconnectDevice.mockResolvedValue({ success: true, data: undefined });

      const result = await useCase.closeSession({ sessionId: SESSION_ID });

      expect(result.success).toBe(true);
      expect(mockSessionService.closeSession).toHaveBeenCalledWith(SESSION_ID);
      expect(mockDeviceService.disconnectDevice).toHaveBeenCalledWith(DEVICE_ID);
    });

    it('should fail if session not found', async () => {
      mockSessionService.getSession.mockResolvedValue({ success: true, data: null });

      const result = await useCase.closeSession({ sessionId: SESSION_ID });

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.code).toBe(ErrorCode.SESSION_NOT_FOUND);
      }
    });

    it('should handle session close failure', async () => {
      const session = Session.create({
        deviceId: DEVICE_ID,
        connectedAt: Date.now(),
        lastActivity: Date.now(),
      });

      mockSessionService.getSession.mockResolvedValue({ success: true, data: session });
      mockSessionService.closeSession.mockResolvedValue({
        success: false,
        error: new CicadaError('Close failed', ErrorCode.SYSTEM_ERROR, {
          severity: ErrorSeverity.HIGH,
        }),
      });

      const result = await useCase.closeSession({ sessionId: SESSION_ID });

      expect(result.success).toBe(false);
      expect(mockDeviceService.disconnectDevice).not.toHaveBeenCalled();
    });
  });

  describe('updateActivity', () => {
    it('should update session activity', async () => {
      const session = Session.create({
        deviceId: DEVICE_ID,
        connectedAt: Date.now(),
        lastActivity: Date.now(),
      });

      mockSessionService.updateActivity.mockResolvedValue({ success: true, data: session });

      const result = await useCase.updateActivity(SESSION_ID);

      expect(result.success).toBe(true);
      expect(mockSessionService.updateActivity).toHaveBeenCalledWith(SESSION_ID);
    });
  });

  describe('recordMessage', () => {
    it('should record message for session', async () => {
      mockSessionService.recordMessage.mockResolvedValue({ success: true, data: undefined });

      const result = await useCase.recordMessage(SESSION_ID);

      expect(result.success).toBe(true);
      expect(mockSessionService.recordMessage).toHaveBeenCalledWith(SESSION_ID);
    });
  });

  describe('cleanupExpiredSessions', () => {
    it('should cleanup expired sessions', async () => {
      mockSessionService.cleanupExpiredSessions.mockResolvedValue({ success: true, data: 3 });

      const result = await useCase.cleanupExpiredSessions(30000);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBe(3);
      }
    });

    it('should handle cleanup errors', async () => {
      mockSessionService.cleanupExpiredSessions.mockResolvedValue({
        success: false,
        error: new CicadaError('Cleanup failed', ErrorCode.SYSTEM_ERROR, {
          severity: ErrorSeverity.HIGH,
        }),
      });

      const result = await useCase.cleanupExpiredSessions(30000);

      expect(result.success).toBe(false);
    });
  });
});
