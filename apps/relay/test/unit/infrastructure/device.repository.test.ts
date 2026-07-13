import { DeviceCapability } from '../../../src/domain/device/device.entity';
import { DeviceRepositoryImpl } from '../../../src/infrastructure/persistence/repositories/device.repository.impl';

function createStorage(value: unknown): DurableObjectStorage {
  return {
    get: jest.fn().mockResolvedValue(value),
  } as unknown as DurableObjectStorage;
}

const persistedDevice = {
  deviceId: 'device-1',
  platform: 'macOS',
  version: '1.0.0',
  capabilities: [DeviceCapability.SYSTEM_INFO],
  metadata: {},
  connectionStatus: 'disconnected',
};

describe('DeviceRepositoryImpl', () => {
  it('restores known persisted capabilities', async () => {
    const repository = new DeviceRepositoryImpl(createStorage(persistedDevice));

    const result = await repository.findById('device-1');

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data?.capabilities).toEqual([DeviceCapability.SYSTEM_INFO]);
    }
  });

  it('rejects unknown persisted capabilities at the storage boundary', async () => {
    const repository = new DeviceRepositoryImpl(
      createStorage({ ...persistedDevice, capabilities: ['unknown_capability'] })
    );

    const result = await repository.findById('device-1');

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.context?.cause).toContain('invalid capabilities');
    }
  });
});
