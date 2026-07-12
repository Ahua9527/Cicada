import {
  methodNotAllowed,
  normalizeShortcutCommands,
  readJsonObject,
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
});
