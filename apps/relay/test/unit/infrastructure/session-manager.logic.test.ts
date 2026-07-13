import {
  extractShortcutToken,
  methodNotAllowed,
  normalizeShortcutGrant,
  normalizeShortcutCommands,
  parseShortcutCommandPayload,
  readJsonObject,
  shortcutErrorResponse,
  shortcutFailureStatus,
} from '../../../src/infrastructure/persistence/durable-objects/session-manager.logic';

describe('SessionManager pure logic', () => {
  it.each([
    ['grant_expired', 403],
    ['grant_revoked', 403],
    ['command_not_allowed', 403],
    ['agent_unavailable', 503],
    ['command_timeout', 504],
    ['unknown', 400],
    [undefined, 400],
  ])('maps shortcut failure %s to %s', (code, expected) => {
    expect(shortcutFailureStatus(code)).toBe(expected);
  });

  it('normalizes, deduplicates, and preserves shortcut command order', () => {
    expect(normalizeShortcutCommands([' ping ', 'status', 'ping', '', '  '])).toEqual([
      'ping',
      'status',
    ]);
    expect(normalizeShortcutCommands(undefined)).toEqual([]);
  });

  it('maps method-not-allowed responses without DO state', async () => {
    const response = methodNotAllowed(['GET', 'POST']);

    expect(response.status).toBe(405);
    expect(response.headers.get('Allow')).toBe('GET, POST');
    expect(await response.json()).toEqual({ success: false, error: 'Method not allowed' });
  });

  it('accepts only JSON objects', async () => {
    const valid = await readJsonObject(
      new Request('http://session', { method: 'POST', body: '{"command":"ping"}' })
    );
    const array = await readJsonObject(
      new Request('http://session', { method: 'POST', body: '["ping"]' })
    );
    const malformed = await readJsonObject(
      new Request('http://session', { method: 'POST', body: '{' })
    );

    expect(valid).toEqual({ command: 'ping' });
    expect(array).toBeUndefined();
    expect(malformed).toBeUndefined();
  });

  it('normalizes valid shortcut grants against an injected clock', () => {
    expect(
      normalizeShortcutGrant(
        'device-1',
        {
          grantId: ' grant-1 ',
          name: ' Desk ',
          tokenHash: ' hash ',
          tokenPreview: ' preview ',
          allowedCommands: [' ping ', 'ping', 'status'],
          expiresAt: 2_000,
        },
        1_000
      )
    ).toEqual({
      grantId: 'grant-1',
      deviceId: 'device-1',
      name: 'Desk',
      tokenHash: 'hash',
      tokenPreview: 'preview',
      allowedCommands: ['ping', 'status'],
      expiresAt: 2_000,
      revokedAt: undefined,
      createdAt: 1_000,
      updatedAt: 1_000,
    });
    expect(
      normalizeShortcutGrant(
        'device-1',
        {
          grantId: 'grant-1',
          name: 'Desk',
          tokenHash: 'hash',
          tokenPreview: 'preview',
          allowedCommands: ['ping'],
          expiresAt: 1_000,
        },
        1_000
      )
    ).toBeUndefined();
  });

  it('extracts only well-formed shortcut bearer tokens', () => {
    expect(
      extractShortcutToken(
        new Request('http://session', {
          headers: { Authorization: 'Bearer cicada_sc_abc-123_xyz' },
        })
      )
    ).toBe('cicada_sc_abc-123_xyz');
    expect(
      extractShortcutToken(
        new Request('http://session', { headers: { Authorization: 'Basic secret' } })
      )
    ).toBeUndefined();
  });

  it('normalizes shortcut command fields and preserves request-id fallback semantics', () => {
    expect(
      parseShortcutCommandPayload(
        { device_id: ' device-1 ', command: ' ping ', request_id: ' req-1 ' },
        'fallback'
      )
    ).toEqual({ deviceId: 'device-1', command: 'ping', requestId: 'req-1' });
    expect(parseShortcutCommandPayload({}, 'fallback')).toEqual({
      deviceId: '',
      command: '',
      requestId: 'fallback',
    });
  });

  it('maps shortcut errors without DO state', async () => {
    const response = shortcutErrorResponse(
      'grant_revoked',
      'Shortcut grant has been revoked.',
      403,
      1_234,
      'req-1',
      'ping'
    );

    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({
      ok: false,
      request_id: 'req-1',
      command: 'ping',
      code: 'grant_revoked',
      error: 'Shortcut grant has been revoked.',
      timestamp: 1_234,
    });
  });
});
