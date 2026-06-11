/**
 * Bark Worker vendor route adapter.
 *
 * The vendored Worker remains isolated under apps/relay/vendor/bark-worker.
 * This adapter only bridges Cicada environment names and route mounting.
 */

import type { Env, MiddlewareContext } from '../../types';
import barkWorker from '../../../vendor/bark-worker/main.js';
import { getBarkRootPath } from './bark-path';

export const BARK_ROUTE_METHODS = ['GET', 'POST', 'DELETE', 'PUT', 'PATCH', 'OPTIONS'];

type BarkWorkerModule = {
  fetch(request: Request, env: Record<string, unknown>, ctx: ExecutionContext): Promise<Response>;
};

const vendoredBarkWorker = barkWorker as BarkWorkerModule;

export async function handleBarkRoute(context: MiddlewareContext): Promise<Response> {
  if (!context.env.BARK_DATABASE) {
    return Response.json(
      {
        ok: false,
        error: 'Bark database binding is not configured',
      },
      { status: 503 }
    );
  }

  const request = rewriteRequestForBark(context.request, getBarkRootPath(context.env));
  const env = createBarkEnv(context.env);
  const executionContext = context.executionContext ?? createDetachedExecutionContext();

  return vendoredBarkWorker.fetch(request, env, executionContext);
}

function createBarkEnv(env: Env): Record<string, unknown> {
  return {
    ...env,
    database: env.BARK_DATABASE,
    ROOT_PATH: '/',
    BASIC_AUTH: env.BARK_BASIC_AUTH ?? env.BASIC_AUTH,
    ALLOW_NEW_DEVICE: env.BARK_ALLOW_NEW_DEVICE,
    ALLOW_QUERY_NUMS: env.BARK_ALLOW_QUERY_NUMS,
  };
}

function rewriteRequestForBark(request: Request, rootPath: string): Request {
  if (rootPath === '/') {
    return request;
  }

  const url = new URL(request.url);
  url.pathname = url.pathname === rootPath ? '/' : url.pathname.slice(rootPath.length);

  const body = request.method === 'GET' || request.method === 'HEAD' ? undefined : request.body;
  const init = {
    method: request.method,
    headers: request.headers,
    body,
    redirect: request.redirect,
    duplex: body ? 'half' : undefined,
  } as RequestInit & { duplex?: 'half' };

  return new Request(url.toString(), init);
}

function createDetachedExecutionContext(): ExecutionContext {
  return {
    waitUntil() {},
    passThroughOnException() {},
  } as unknown as ExecutionContext;
}
