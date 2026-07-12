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
