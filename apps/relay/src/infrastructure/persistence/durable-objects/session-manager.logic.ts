export function shortcutFailureStatus(code?: string): number {
  switch (code) {
    case 'grant_expired':
    case 'grant_revoked':
    case 'command_not_allowed':
      return 403;
    case 'agent_unavailable':
      return 503;
    case 'command_timeout':
      return 504;
    default:
      return 400;
  }
}

export function methodNotAllowed(allowed: string[]): Response {
  return Response.json(
    {
      success: false,
      error: 'Method not allowed',
    },
    {
      status: 405,
      headers: {
        Allow: allowed.join(', '),
      },
    }
  );
}

export function normalizeShortcutCommands(value?: string[]): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return Array.from(
    new Set(
      value
        .filter(command => typeof command === 'string')
        .map(command => command.trim())
        .filter(Boolean)
    )
  );
}

export function normalizeShortcutGrant(
  deviceId: string,
  value: Partial<ShortcutGrantRecord> | undefined,
  now: number
): ShortcutGrantRecord | undefined {
  if (!value || typeof value !== 'object') {
    return undefined;
  }
  const grantId = typeof value.grantId === 'string' ? value.grantId.trim() : '';
  const name = typeof value.name === 'string' ? value.name.trim() : '';
  const tokenHash = typeof value.tokenHash === 'string' ? value.tokenHash.trim() : '';
  const tokenPreview = typeof value.tokenPreview === 'string' ? value.tokenPreview.trim() : '';
  const allowedCommands = normalizeShortcutCommands(value.allowedCommands);
  const expiresAt = typeof value.expiresAt === 'number' ? value.expiresAt : 0;
  const createdAt = typeof value.createdAt === 'number' ? value.createdAt : now;
  const updatedAt = typeof value.updatedAt === 'number' ? value.updatedAt : now;
  if (!grantId || !name || !tokenHash || !tokenPreview || allowedCommands.length === 0 || expiresAt <= now) {
    return undefined;
  }
  return {
    grantId,
    deviceId,
    name,
    tokenHash,
    tokenPreview,
    allowedCommands,
    expiresAt,
    revokedAt: typeof value.revokedAt === 'number' ? value.revokedAt : undefined,
    createdAt,
    updatedAt,
  };
}

export function extractShortcutToken(request: Request): string | undefined {
  const authorization =
    request.headers.get('Authorization') ?? request.headers.get('authorization') ?? '';
  return authorization.match(/^Bearer\s+(cicada_sc_[A-Za-z0-9_-]+)$/)?.[1];
}

export function parseShortcutCommandPayload(
  payload: Record<string, unknown>,
  fallbackRequestId: string
): ShortcutCommandPayload {
  const deviceId = typeof payload.device_id === 'string' ? payload.device_id.trim() : '';
  const command = typeof payload.command === 'string' ? payload.command.trim() : '';
  const requestId =
    typeof payload.request_id === 'string' && payload.request_id.trim()
      ? payload.request_id.trim()
      : fallbackRequestId;
  const params =
    payload.params && typeof payload.params === 'object' && !Array.isArray(payload.params)
      ? (payload.params as Record<string, unknown>)
      : undefined;
  return { deviceId, command, requestId, params };
}

export function shortcutErrorResponse(
  code: string,
  error: string,
  status: number,
  timestamp: number,
  requestId = '',
  command = ''
): Response {
  return Response.json(
    {
      ok: false,
      request_id: requestId,
      command,
      code,
      error,
      timestamp,
    },
    { status }
  );
}

export async function readJsonObject(
  request: Request
): Promise<Record<string, unknown> | undefined> {
  try {
    const payload = await request.json();
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
      return undefined;
    }
    return payload as Record<string, unknown>;
  } catch {
    return undefined;
  }
}
import type { ShortcutGrantRecord } from '@cicada/shared';

export type ShortcutCommandPayload = {
  deviceId: string;
  command: string;
  requestId: string;
  params?: Record<string, unknown>;
};
