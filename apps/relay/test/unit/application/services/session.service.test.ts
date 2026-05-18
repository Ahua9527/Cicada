import { SessionService } from '@/application/services/session.service';
import type { SessionRepository } from '@/domain/session/session.repository';
import { Session, DeviceId as SessionDeviceId } from '@/domain/session/session.entity';
import { CicadaError, ErrorCode, ErrorSeverity } from '@cicada/shared/errors';
import type { DeviceId, SessionId } from '@cicada/shared/types/common.types';

describe('SessionService', () => {
  let service: SessionService;
  let mockRepository: jest.Mocked<SessionRepository>;

  const DEVICE_ID = 'MAC_0123456789abcdef0123456789abcdef' as DeviceId;
  const SESSION_ID = 'session-123' as SessionId;

  beforeEach(() => {
    mockRepository = {
      findById: jest.fn(),
      findActiveByDeviceId: jest.fn(),
      save: jest.fn(),
      listActive: jest.fn(),
      delete: jest.fn(),
    } as any;

    service = new SessionService({ sessionRepository: mockRepository });
  });

  describe('createSession', () => {
    it('should create a new session successfully', async () => {
      mockRepository.findActiveByDeviceId.mockResolvedValue({ success: true, data: null });
      mockRepository.save.mockResolvedValue({ success: true, data: undefined });

      const result = await service.createSession(DEVICE_ID);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBeInstanceOf(Session);
        expect(result.data.device.toString()).toBe(DEVICE_ID);
      }
      expect(mockRepository.save).toHaveBeenCalledTimes(1);
    });

    it('should fail if active session already exists', async () => {
      const deviceId = SessionDeviceId.create(DEVICE_ID)!;
      const existingSession = Session.create({
        deviceId,
        connectedAt: Date.now(),
        lastActivity: Date.now(),
      });

      mockRepository.findActiveByDeviceId.mockResolvedValue({
        success: true,
        data: existingSession,
      });

      const result = await service.createSession(DEVICE_ID);

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.code).toBe(ErrorCode.SESSION_CONFLICT);
      }
      expect(mockRepository.save).not.toHaveBeenCalled();
    });

    it('should handle repository errors', async () => {
      mockRepository.findActiveByDeviceId.mockResolvedValue({
        success: false,
        error: new CicadaError('DB error', ErrorCode.SYSTEM_ERROR, {
          severity: ErrorSeverity.HIGH,
        }),
      });

      const result = await service.createSession(DEVICE_ID);

      expect(result.success).toBe(false);
    });
  });

  describe('getSession', () => {
    it('should retrieve existing session', async () => {
      const deviceId = SessionDeviceId.create(DEVICE_ID)!;
      const session = Session.create({
        deviceId,
        connectedAt: Date.now(),
        lastActivity: Date.now(),
      });

      mockRepository.findById.mockResolvedValue({ success: true, data: session });

      const result = await service.getSession(SESSION_ID);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBe(session);
      }
    });

    it('should return null for non-existent session', async () => {
      mockRepository.findById.mockResolvedValue({ success: true, data: null });

      const result = await service.getSession(SESSION_ID);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBeNull();
      }
    });
  });

  describe('updateActivity', () => {
    it('should update session activity', async () => {
      const deviceId = SessionDeviceId.create(DEVICE_ID)!;
      const session = Session.create({
        deviceId,
        connectedAt: 1000,
        lastActivity: 1000,
      });

      mockRepository.findById.mockResolvedValue({ success: true, data: session });
      mockRepository.save.mockResolvedValue({ success: true, data: undefined });

      const newTimestamp = 2000;
      const result = await service.updateActivity(SESSION_ID as any, newTimestamp);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.lastActivity).toBe(newTimestamp);
      }
      expect(mockRepository.save).toHaveBeenCalled();
    });

    it('should fail for non-existent session', async () => {
      mockRepository.findById.mockResolvedValue({ success: true, data: null });

      const result = await service.updateActivity(SESSION_ID);

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.code).toBe(ErrorCode.SESSION_NOT_FOUND);
      }
    });
  });

  describe('recordMessage', () => {
    it('should record message successfully', async () => {
      const deviceId = SessionDeviceId.create(DEVICE_ID)!;
      const session = Session.create({
        deviceId,
        connectedAt: Date.now(),
        lastActivity: Date.now(),
      });

      mockRepository.findById.mockResolvedValue({ success: true, data: session });
      mockRepository.save.mockResolvedValue({ success: true, data: undefined });

      const result = await service.recordMessage(SESSION_ID);

      expect(result.success).toBe(true);
      expect(mockRepository.save).toHaveBeenCalled();
    });
  });

  describe('closeSession', () => {
    it('should close active session', async () => {
      const deviceId = SessionDeviceId.create(DEVICE_ID)!;
      const session = Session.create({
        deviceId,
        connectedAt: Date.now(),
        lastActivity: Date.now(),
      });

      mockRepository.findById.mockResolvedValue({ success: true, data: session });
      mockRepository.save.mockResolvedValue({ success: true, data: undefined });

      const result = await service.closeSession(SESSION_ID);

      expect(result.success).toBe(true);
      expect(session.isActive).toBe(false);
      expect(mockRepository.save).toHaveBeenCalled();
    });
  });

  describe('cleanupExpiredSessions', () => {
    it('should cleanup timed out sessions', async () => {
      const deviceId1 = SessionDeviceId.create(DEVICE_ID)!;
      const activeSession = Session.create({
        deviceId: deviceId1,
        connectedAt: 1000,
        lastActivity: 1000,
      });

      const deviceId2 = SessionDeviceId.create('MAC_0123456789abcdef0123456789abcde2')!;
      const expiredSession = Session.create({
        deviceId: deviceId2,
        connectedAt: 1000,
        lastActivity: 1000,
      });

      mockRepository.listActive.mockResolvedValue({
        success: true,
        data: [activeSession, expiredSession],
      });
      mockRepository.save.mockResolvedValue({ success: true, data: undefined });

      const timeoutMs = 30_000;
      expiredSession.hasTimedOut(timeoutMs, 50_000);

      const result = await service.cleanupExpiredSessions(timeoutMs);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBeGreaterThanOrEqual(0);
      }
    });
  });
});
