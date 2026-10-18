import { DeviceId, Session } from '@/domain/session/session.entity';

describe('Session Aggregate', () => {
  const DEVICE_ID = 'MAC_0123456789abcdef0123456789abcdef';

  it('marks session inactive when timeout threshold exceeded', () => {
    const deviceId = DeviceId.create(DEVICE_ID);
    expect(deviceId).not.toBeNull();
    if (!deviceId) {
      return;
    }

    const baseTime = 1_700_000_000_000;
    const session = Session.create({
      deviceId,
      connectedAt: baseTime,
      lastActivity: baseTime,
    });

    const timedOut = session.hasTimedOut(30_000, baseTime + 60_000);
    expect(timedOut).toBe(true);
    expect(session.isActive).toBe(false);
    expect(session.needsCleanup()).toBe(true);
    expect(session.getMetrics().timeoutCount).toBe(1);
  });

  it('tracks total messages sent through recordMessage', () => {
    const deviceId = DeviceId.create(DEVICE_ID);
    expect(deviceId).not.toBeNull();
    if (!deviceId) {
      return;
    }

    const session = Session.create({
      deviceId,
      connectedAt: 1,
      lastActivity: 1,
    });

    session.recordMessage(10);
    session.recordMessage(20);

    const metrics = session.getMetrics();
    expect(metrics.totalMessages).toBe(2);
    expect(session.lastActivity).toBe(20);
  });
});
