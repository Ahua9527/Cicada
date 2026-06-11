import type { Env } from '../../types';

export const DEFAULT_BARK_ROOT_PATH = '/bark';

export function getBarkRootPath(env: Env): string {
  const configuredRootPath = env.BARK_ROOT_PATH?.trim();
  const configured =
    configuredRootPath && configuredRootPath.length > 0
      ? configuredRootPath
      : DEFAULT_BARK_ROOT_PATH;

  if (configured === '/') {
    return '/';
  }

  const rooted = configured.startsWith('/') ? configured : `/${configured}`;
  return rooted.replace(/\/+$/, '');
}

export function isBarkRequest(pathname: string, env: Env): boolean {
  const rootPath = getBarkRootPath(env);

  if (rootPath === '/') {
    return true;
  }

  return pathname === rootPath || pathname.startsWith(`${rootPath}/`);
}
