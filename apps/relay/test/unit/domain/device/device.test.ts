import { Device, DeviceCapability, DeviceConnectionStatus } from '@/domain/device';

describe('Device Aggregate', () => {
  const DEVICE_ID = 'MAC_0123456789abcdef0123456789abcdef';
  const PLATFORM = 'macOS';
  const VERSION = '14.0';

  describe('Device Entity', () => {
    it('creates device with default values', () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: PLATFORM,
        version: VERSION,
      });

      expect(device.id).toBe(DEVICE_ID);
      expect(device.platform).toBe(PLATFORM);
      expect(device.version).toBe(VERSION);
      expect(device.deviceType).toBe('unknown');
      expect(device.connectionStatus).toBe(DeviceConnectionStatus.DISCONNECTED);
      expect(device.isConnected).toBe(false);
    });

    it('creates device with capabilities', () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: PLATFORM,
        version: VERSION,
        capabilities: [DeviceCapability.LOCK_SCREEN, DeviceCapability.BLUETOOTH_CONTROL],
      });

      expect(device.capabilities).toHaveLength(2);
      expect(device.hasCapability(DeviceCapability.LOCK_SCREEN)).toBe(true);
      expect(device.hasCapability(DeviceCapability.SLEEP_CONTROL)).toBe(false);
    });

    it('adds and removes capabilities', () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: PLATFORM,
        version: VERSION,
      });

      expect(device.hasCapability(DeviceCapability.LOCK_SCREEN)).toBe(false);

      device.addCapability(DeviceCapability.LOCK_SCREEN);
      expect(device.hasCapability(DeviceCapability.LOCK_SCREEN)).toBe(true);

      device.removeCapability(DeviceCapability.LOCK_SCREEN);
      expect(device.hasCapability(DeviceCapability.LOCK_SCREEN)).toBe(false);
    });

    it('updates metadata', () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: PLATFORM,
        version: VERSION,
      });

      device.updateMetadata({
        name: 'MacBook Pro',
        model: 'MacBookPro18,1',
      });

      const metadata = device.metadata;
      expect(metadata.name).toBe('MacBook Pro');
      expect(metadata.model).toBe('MacBookPro18,1');
    });

    it('marks device as connected with session', () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: PLATFORM,
        version: VERSION,
      });

      const sessionId = 'session-123';
      device.markConnected(sessionId);

      expect(device.isConnected).toBe(true);
      expect(device.connectionStatus).toBe(DeviceConnectionStatus.CONNECTED);
      expect(device.sessionId).toBe(sessionId);
    });

    it('marks device as disconnected', () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: PLATFORM,
        version: VERSION,
      });

      device.markConnected('session-123');
      expect(device.isConnected).toBe(true);

      device.markDisconnected();
      expect(device.isConnected).toBe(false);
      expect(device.sessionId).toBeNull();
    });

    it('records ping activity', () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: PLATFORM,
        version: VERSION,
        lastSeen: 1000,
      });

      device.recordPing(2000);
      expect(device.lastSeen).toBe(2000);
    });

    it('records message and increments counter', () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: PLATFORM,
        version: VERSION,
      });

      device.recordMessage();
      device.recordMessage();

      const status = device.toDeviceStatus();
      expect(status.messagesExchanged).toBe(2);
    });

    it('detects timeout when connected', () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: PLATFORM,
        version: VERSION,
      });

      const baseTime = 1000;
      device.markConnected('session-123', baseTime);

      expect(device.hasTimedOut(30000, baseTime + 20000)).toBe(false);
      expect(device.hasTimedOut(30000, baseTime + 40000)).toBe(true);
    });

    it('does not detect timeout when disconnected', () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: PLATFORM,
        version: VERSION,
      });

      expect(device.hasTimedOut(30000, Date.now() + 100000)).toBe(false);
    });

    it('converts to DeviceInfo', () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: PLATFORM,
        version: VERSION,
        deviceType: 'mac',
        capabilities: [DeviceCapability.LOCK_SCREEN],
      });

      device.markConnected('session-123');

      const info = device.toDeviceInfo();
      expect(info.deviceId).toBe(DEVICE_ID);
      expect(info.platform).toBe(PLATFORM);
      expect(info.version).toBe(VERSION);
      expect(info.deviceType).toBe('mac');
      expect(info.sessionActive).toBe(true);
      expect(info.sessionId).toBe('session-123');
      expect(info.capabilities).toContain(DeviceCapability.LOCK_SCREEN);
    });

    it('converts to DeviceStatus', () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: PLATFORM,
        version: VERSION,
        metadata: {
          ipAddress: '192.168.1.100',
          userAgent: 'Cicada/1.0',
        },
      });

      device.markConnected('session-123', 1000);
      device.recordPing(2000);

      const status = device.toDeviceStatus();
      expect(status.deviceId).toBe(DEVICE_ID);
      expect(status.connected).toBe(true);
      expect(status.connectedAt).toBe(1000);
      expect(status.lastPing).toBe(2000);
      expect(status.ipAddress).toBe('192.168.1.100');
      expect(status.userAgent).toBe('Cicada/1.0');
    });

    it('tracks uptime across connections', () => {
      const device = Device.create({
        deviceId: DEVICE_ID,
        platform: PLATFORM,
        version: VERSION,
        uptime: 0,
      });

      device.markConnected('session-1', 1000);
      device.markDisconnected(11000); // 10 seconds

      device.markConnected('session-2', 12000);
      device.markDisconnected(22000); // 10 seconds

      const status = device.toDeviceStatus();
      expect(status.uptime).toBe(20000);
    });
  });
});
