const FILTERED = '[FILTERED]';
const SENSITIVE_QUERY_KEYS = new Set([
  'api_key',
  'nonce',
  'signature',
  'token',
  'code',
]);

export function sanitizeRequestUrl(rawUrl: string | URL): string {
  const url = new URL(rawUrl.toString());
  redactRelayPath(url);
  redactSensitiveQuery(url);
  return url.toString();
}

function redactRelayPath(url: URL): void {
  if (!url.pathname.startsWith('/relay/')) {
    return;
  }

  const [, relay, ...rest] = url.pathname.split('/');
  url.pathname = `/${relay}/[session]${rest.length > 1 ? `/${rest.slice(1).join('/')}` : ''}`;
}

function redactSensitiveQuery(url: URL): void {
  for (const key of Array.from(url.searchParams.keys())) {
    if (SENSITIVE_QUERY_KEYS.has(key.toLowerCase())) {
      url.searchParams.set(key, FILTERED);
    }
  }
}
