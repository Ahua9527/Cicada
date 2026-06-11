import type { Env } from '../types';
import { DEFAULT_BARK_ROOT_PATH, getBarkRootPath } from './routes/bark-path';

const FILTERED = '[FILTERED]';
const SENSITIVE_QUERY_KEYS = new Set([
  'api_key',
  'nonce',
  'signature',
  'token',
  'code',
  'devicetoken',
  'device_token',
  'device_key',
  'device_keys',
  'title',
  'body',
  'message',
  'subtitle',
  'group',
]);

const BARK_ENDPOINTS_WITHOUT_PATH_SECRETS = new Set([
  'register',
  'ping',
  'healthz',
  'info',
  'push',
  'mcp',
]);

export function sanitizeRequestUrl(rawUrl: string | URL, env?: Env): string {
  const url = new URL(rawUrl.toString());
  redactRelayPath(url);
  redactBarkPath(url, env ?? ({} as Env));
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

function redactBarkPath(url: URL, env: Env): void {
  const rootPath = findBarkRootForLogging(url.pathname, env);
  if (!rootPath) {
    return;
  }

  const prefix = rootPath === '/' ? '' : rootPath;
  const relativePath = rootPath === '/' ? url.pathname : url.pathname.slice(rootPath.length);
  const segments = relativePath.split('/').filter(Boolean);
  if (segments.length === 0) {
    url.pathname = rootPath;
    return;
  }

  const firstSegment = segments[0];
  if (BARK_ENDPOINTS_WITHOUT_PATH_SECRETS.has(firstSegment.toLowerCase())) {
    url.pathname = `${prefix}/${firstSegment}`;
    return;
  }

  url.pathname = `${prefix}/[device_key]${segments.length > 1 ? '/[payload]' : ''}`;
}

function findBarkRootForLogging(pathname: string, env: Env): string | undefined {
  if (isReservedCicadaPath(pathname)) {
    return undefined;
  }

  const configuredRootPath = getBarkRootPath(env);
  const candidateRoots =
    configuredRootPath === DEFAULT_BARK_ROOT_PATH
      ? [DEFAULT_BARK_ROOT_PATH]
      : [configuredRootPath, DEFAULT_BARK_ROOT_PATH];

  return candidateRoots.find(rootPath => {
    if (rootPath === '/') {
      return true;
    }

    return pathname === rootPath || pathname.startsWith(`${rootPath}/`);
  });
}

function isReservedCicadaPath(pathname: string): boolean {
  return (
    pathname === '/' ||
    pathname === '/favicon.ico' ||
    pathname === '/health' ||
    pathname === '/status' ||
    pathname === '/devices' ||
    pathname === '/v1/shortcuts/command' ||
    pathname.startsWith('/relay/')
  );
}

function redactSensitiveQuery(url: URL): void {
  for (const key of Array.from(url.searchParams.keys())) {
    if (SENSITIVE_QUERY_KEYS.has(key.toLowerCase())) {
      url.searchParams.set(key, FILTERED);
    }
  }
}
