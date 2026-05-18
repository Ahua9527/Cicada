import { DeviceService } from '@/application/services/device.service';
import type { DeviceRepository } from '@/domain/device/device.repository';
import { Device } from '@/domain/device/device.entity';
import { CicadaError, ErrorCode, ErrorSeverity } from '@cicada/shared/errors';
import type { DeviceId } from '@cicada/shared/types/common.types';

describe('DeviceService', () => {
  let service: DeviceService;
  let mockRepository: jest.Mocked<DeviceRepository>;

  const DEVICE_ID = 'MAC_0123456789abcdef0123456789abcdef' as DeviceId;
  const SESSION_ID = 'session-123';

  beforeEach(() => {
    mockRepository = {
      findById: jest.fn(),
      save: jest.fn(),
      delete: jest.fn(),
      listAll: jest.fn(),
    } as any;

    service = new DeviceService({ deviceRepository: mockRepository });
  });

  describe('registerDevice', () => {
    it('should register a new device', async () => {
      mockRepository.findById.mockResolvedValue({ success: true, data: null });
      mockRepository.save.mockResolvedValue({ success: true, data: undefined });

      const result = await service.registerDevice(DEVICE_ID, 'macOS', '1.0.0');

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBeInstanceOf(Device);
        expect(result.data.id).toBe(DEVICE_ID);
      }
      expect(mockRepository.save).toHaveBeenCalledTimes(1);
    });

    it('should update existing device', async () => {
      const existingDevice = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      mockRepository.findById.mockResolvedValue({ success: true, data: existingDevice });
      mockRepository.save.mockResolvedValue({ success: true, data: undefined });

      const result = await service.registerDevice(DEVICE_ID, 'macOS', '1.1.0', {
        hostname: 'test-mac',
      });

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBe(existingDevice);
      }
      expect(mockRepository.save).toHaveBeenCalled();
    });

    it('should handle repository errors', async () => {
      mockRepository.findById.mockResolvedValue({
        success: false,
        error: new CicadaError('DB error', ErrorCode.SYSTEM_ERROR, {
          severity: ErrorSeverity.HIGH,
        }),
      });

      const result = await service.registerDevice(DEVICE_ID, 'macOS', '1.0.0');

      expect(result.success).toBe(false);
    });
  });

  describe('getDevice', () => {
    it('should retrieve existing device', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      mockRepository.findById.mockResolvedValue({ success: true, data: device });

      const result = await service.getDevice(DEVICE_ID);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBe(device);
      }
    });

    it('should return null for non-existent device', async () => {
      mockRepository.findById.mockResolvedValue({ success: true, data: null });

      const result = await service.getDevice(DEVICE_ID);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBeNull();
      }
    });
  });

  describe('updateMetadata', () => {
    it('should update device metadata', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      mockRepository.findById.mockResolvedValue({ success: true, data: device });
      mockRepository.save.mockResolvedValue({ success: true, data: undefined });

      const result = await service.updateMetadata(DEVICE_ID, {
        hostname: 'updated-mac',
      });

      expect(result.success).toBe(true);
      expect(mockRepository.save).toHaveBeenCalled();
    });

    it('should fail for non-existent device', async () => {
      mockRepository.findById.mockResolvedValue({ success: true, data: null });

      const result = await service.updateMetadata(DEVICE_ID, {});

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.code).toBe(ErrorCode.DEVICE_NOT_FOUND);
      }
    });
  });

  describe('connectDevice', () => {
    it('should mark device as connected', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      mockRepository.findById.mockResolvedValue({ success: true, data: device });
      mockRepository.save.mockResolvedValue({ success: true, data: undefined });

      const result = await service.connectDevice(DEVICE_ID, SESSION_ID);

      expect(result.success).toBe(true);
      expect(device.sessionId).toBe(SESSION_ID);
      expect(mockRepository.save).toHaveBeenCalled();
    });

    it('should fail for non-existent device', async () => {
      mockRepository.findById.mockResolvedValue({ success: true, data: null });

      const result = await service.connectDevice(DEVICE_ID, SESSION_ID);

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.code).toBe(ErrorCode.DEVICE_NOT_FOUND);
      }
    });
  });

  describe('disconnectDevice', () => {
    it('should mark device as disconnected', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });
      device.markConnected(SESSION_ID);

      mockRepository.findById.mockResolvedValue({ success: true, data: device });
      mockRepository.save.mockResolvedValue({ success: true, data: undefined });

      const result = await service.disconnectDevice(DEVICE_ID);

      expect(result.success).toBe(true);
      expect(device.sessionId).toBeNull();
      expect(mockRepository.save).toHaveBeenCalled();
    });

    it('should succeed for already disconnected device', async () => {
      mockRepository.findById.mockResolvedValue({ success: true, data: null });

      const result = await service.disconnectDevice(DEVICE_ID);

      expect(result.success).toBe(true);
    });
  });

  describe('recordPing', () => {
    it('should update last ping timestamp', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      mockRepository.findById.mockResolvedValue({ success: true, data: device });
      mockRepository.save.mockResolvedValue({ success: true, data: undefined });

      const result = await service.recordPing(DEVICE_ID);

      expect(result.success).toBe(true);
      expect(mockRepository.save).toHaveBeenCalled();
    });

    it('should fail for non-existent device', async () => {
      mockRepository.findById.mockResolvedValue({ success: true, data: null });

      const result = await service.recordPing(DEVICE_ID);

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.code).toBe(ErrorCode.DEVICE_NOT_FOUND);
      }
    });
  });

  describe('getDeviceInfo', () => {
    it('should return device info', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });

      mockRepository.findById.mockResolvedValue({ success: true, data: device });

      const result = await service.getDeviceInfo(DEVICE_ID);

      expect(result.success).toBe(true);
      if (result.success && result.data) {
        expect(result.data.deviceId).toBe(DEVICE_ID);
        expect(result.data.platform).toBe('macOS');
      }
    });

    it('should return null for non-existent device', async () => {
      mockRepository.findById.mockResolvedValue({ success: true, data: null });

      const result = await service.getDeviceInfo(DEVICE_ID);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBeNull();
      }
    });
  });

  describe('getDeviceStatus', () => {
    it('should return device status', async () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: 'macOS',
        version: '1.0.0',
      });
      device.markConnected(SESSION_ID);

      mockRepository.findById.mockResolvedValue({ success: true, data: device });

      const result = await service.getDeviceStatus(DEVICE_ID);

      expect(result.success).toBe(true);
      if (result.success && result.data) {
        expect(result.data.connected).toBe(true);
      }
    });

    it('should return null for non-existent device', async () => {
      mockRepository.findById.mockResolvedValue({ success: true, data: null });

      const result = await service.getDeviceStatus(DEVICE_ID);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toBeNull();
      }
    });
  });
});
