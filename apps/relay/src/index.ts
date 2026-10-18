/**
 * CicadaRelay - Main Entry Point
 * Cloudflare Worker application entry
 */

import type { Env } from './types';
import { CicadaRelayApp } from './presentation/app';
import { SessionManagerDO } from './infrastructure/persistence';

// Preserve rate-limit counters across requests; env is stable within the same isolate.
let app: CicadaRelayApp | undefined;

/**
 * Cloudflare Worker fetch handler
 */
export default {
  // eslint-disable-next-line no-undef
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    app ??= new CicadaRelayApp(env);
    return app.handle(request, env, ctx);
  },
};

/**
 * Export Durable Object class (required by Cloudflare Workers)
 */
export { SessionManagerDO as CicadaSessionManager };
