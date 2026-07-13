/**
 * Session Controller
 * Handles WebSocket session management
 */

import type { MiddlewareContext } from '../../types';
import { SESSION_CONSTANTS } from '../../config/constants';
import {
  copyDurableObjectResponse,
  toDurableObjectRequest,
  toWorkerResponse,
} from '../../infrastructure/cloudflare/worker-fetch-adapter';
import { createPublicServerErrorResponse } from '../public-error-response';

/**
 * Session Controller
 */
export class SessionController {
  /**
   * Handle WebSocket connection
   */
  static async handleWebSocketConnection(context: MiddlewareContext): Promise<Response> {
    const { request, logger, requestId } = context;
    const url = new URL(request.url);

    if (url.pathname.startsWith('/relay/')) {
      return this.handleRelayTransportConnection(context);
    }

    logger.warn('Unsupported WebSocket route', {
      requestId,
      context: { pathname: url.pathname },
      tags: ['websocket', 'routing'],
    });
    return Response.json(
      {
        ok: false,
        error: 'API endpoint not found',
        path: url.pathname,
      },
      { status: 404 }
    );
  }

  static async sendShortcutCommand(context: MiddlewareContext): Promise<Response> {
    return this.forwardRegistryJSON(context, '/v1/shortcuts/command');
  }

  private static async handleRelayTransportConnection(
    context: MiddlewareContext
  ): Promise<Response> {
    const { request, env, logger, requestId } = context;
    const url = new URL(request.url);
    const target = decodeURIComponent(url.pathname.split('/').pop() ?? '');

    if (!target) {
      return Response.json(
        {
          ok: false,
          error: 'Missing relay target',
          code: 'invalid_relay_connection',
        },
        { status: 400 }
      );
    }

    try {
      const sessionId = target;
      const sessionManager = env.CICADA_SESSIONS.get(env.CICADA_SESSIONS.idFromName(sessionId));
      const headers = new Headers(request.headers);
      headers.set('X-Session-ID', sessionId);
      headers.set('Upgrade', 'websocket');
      headers.set('Connection', 'Upgrade');
      headers.set('X-Request-ID', requestId);

      const deviceId = request.headers.get('x-device-id');
      const publicKey = request.headers.get('x-agent-identity-public-key');
      if (!deviceId || !publicKey) {
        return Response.json(
          {
            ok: false,
            error: 'Agent relay connection requires x-device-id and x-agent-identity-public-key',
            code: 'missing_agent_identity',
          },
          { status: 400 }
        );
      }
      headers.set('X-Device-ID', deviceId);
      headers.set('X-Agent-Identity-Public-Key', publicKey);
      for (const [source, targetHeader] of [
        ['x-agent-registration-timestamp', 'X-Agent-Registration-Timestamp'],
        ['x-agent-registration-nonce', 'X-Agent-Registration-Nonce'],
        ['x-agent-registration-signature', 'X-Agent-Registration-Signature'],
      ]) {
        const value = request.headers.get(source);
        if (value) {
          headers.set(targetHeader, value);
        }
      }

      const forwardedRequest = new Request(request.url, {
        method: request.method,
        headers,
      });
      const response = await sessionManager.fetch(toDurableObjectRequest(forwardedRequest));
      return toWorkerResponse(response);
    } catch (error) {
      logger.error('Relay transport connection failed', {
        requestId,
        error: error as Error,
        tags: ['relay', 'websocket', 'error'],
      });
      return createPublicServerErrorResponse(requestId);
    }
  }

  private static getRegistryStub(env: MiddlewareContext['env']) {
    const registryId = env.CICADA_SESSIONS.idFromName(SESSION_CONSTANTS.REGISTRY_DO_NAME);
    return env.CICADA_SESSIONS.get(registryId);
  }

  private static async forwardRegistryJSON(
    context: MiddlewareContext,
    pathname: string
  ): Promise<Response> {
    const { request, env, logger, requestId } = context;
    try {
      const registry = this.getRegistryStub(env);
      const body = await request.text();
      const headers = new Headers(request.headers);
      headers.set('X-Request-ID', requestId);
      const response = await registry.fetch(
        toDurableObjectRequest(
          new Request(`http://registry${pathname}`, {
            method: request.method,
            headers,
            body,
          })
        )
      );
      return copyDurableObjectResponse(response);
    } catch (error) {
      logger.error('Registry JSON route failed', {
        requestId,
        error: error as Error,
        tags: ['relay', 'registry', 'error'],
      });
      return createPublicServerErrorResponse(requestId);
    }
  }

}
