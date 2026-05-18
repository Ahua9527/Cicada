import { Result } from '@cicada/shared/errors';
import { DeviceId, Session, SessionValidator, SessionValidationError } from '@/domain/session';

describe('Session Aggregate', () => {
  const DEVICE_ID = 'MAC_0123456789abcdef0123456789abcdef';

  it('creates an active session with metadata via validator', () => {
    const validator = new SessionValidator();
    const result = validator.validate({
      deviceId: DEVICE_ID,
      ipAddress: '192.168.0.10',
      userAgent: 'cicada-relay-test',
      connectedAt: 1_700_000_000_000,
      lastActivity: 1_700_000_000_100,
      lastPing: 1_700_000_000_150,
    });

    expect(Result.isOk(result)).toBe(true);
    const session = result.success ? result.data : null;
    expect(session).not.toBeNull();
    if (!session) {
      return;
    }

    expect(session.isActive).toBe(true);
    expect(session.metadata.ipAddress).toBe('192.168.0.10');
    expect(session.metadata.userAgent).toBe('cicada-relay-test');
    expect(session.connectedAt).toBe(1_700_000_000_000);
    expect(session.lastActivity).toBe(1_700_000_000_100);
    expect(session.lastPing).toBe(1_700_000_000_150);
  });

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

  it('rejects invalid device id format', () => {
    const validator = new SessionValidator();
    const result = validator.validate({
      deviceId: 'invalid-device',
    });

    expect(Result.isErr(result)).toBe(true);
    if (result.success) {
      throw new Error('Expected validation to fail');
    }

    expect(result.error).toBeInstanceOf(SessionValidationError);
    expect(result.error.message).toContain('Device ID');
  });

  it('rejects logical timestamp ordering issues', () => {
    const validator = new SessionValidator();
    const result = validator.validate({
      deviceId: DEVICE_ID,
      connectedAt: 100,
      lastActivity: 50,
    });

    expect(Result.isErr(result)).toBe(true);
    if (result.success) {
      throw new Error('Expected validation to fail');
    }

    expect(result.error.message).toContain('lastActivity');
  });
});
