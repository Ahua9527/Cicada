/**
 * Session Controller
 * Handles WebSocket session management
 */

import type { MiddlewareContext } from '../../types';
import { validateWebSocketConnection } from '../../utils/crypto';

/**
 * Session Controller
 */
export class SessionController {
  /**
   * Handle WebSocket connection
   */
  static async handleWebSocketConnection(context: MiddlewareContext): Promise<Response> {
    const { request, env, logger, requestId } = context;
    const url = new URL(request.url);

    console.log('[DEBUG] WebSocket handler started', { requestId });
    logger.info('WebSocket handler started', {
      requestId,
      tags: ['websocket', 'debug'],
    });

    // Get connection parameters
    const deviceId = url.searchParams.get('device_id');
    const apiKey = url.searchParams.get('api_key');
    const timestamp = url.searchParams.get('ts');

    console.log('[DEBUG] Parameters extracted', { deviceId, timestamp });

    // Validate parameters
    if (!deviceId || !apiKey || !timestamp) {
      return Response.json(
        {
          ok: false,
          error: 'Missing connection parameters',
          missing_params: ['device_id', 'api_key', 'ts'].filter(
            param => !url.searchParams.get(param)
          ),
        },
        { status: 400 }
      );
    }

    try {
      // Validate WebSocket connection
      console.log('[DEBUG] Validating connection');
      const ts = parseInt(timestamp);
      const validation = validateWebSocketConnection(deviceId, apiKey, env.API_KEY, ts);
      console.log('[DEBUG] Validation result:', validation.valid);

      if (!validation.valid) {
        console.log('[ERROR] Validation failed:', validation.error);
        logger.warn('WebSocket connection validation failed', {
          requestId,
          context: {
            deviceId,
            error: validation.error,
            details: validation.details,
          },
          tags: ['websocket', 'security', 'error'],
        });

        const statusCode = validation.error === 'INVALID_API_KEY' ? 401 : 400;
        return Response.json(
          {
            ok: false,
            error: validation.details?.message ?? validation.error,
          },
          { status: statusCode }
        );
      }

      // Get device's Durable Object
      console.log('[DEBUG] Getting Durable Object for device:', deviceId);
      const sessionId = env.CICADA_SESSIONS.idFromName(deviceId);
      console.log('[DEBUG] Session ID obtained');
      const sessionManager = env.CICADA_SESSIONS.get(sessionId);
      console.log('[DEBUG] Session manager obtained');

      // Forward the WebSocket upgrade request directly to Durable Object
      console.log('[DEBUG] Forwarding WebSocket upgrade to Durable Object');

      // Create headers without duplicating Upgrade
      const headers = new Headers(request.headers);
      headers.set('X-Device-ID', deviceId);
      headers.set('X-Timestamp', ts.toString());
      headers.set('Upgrade', 'websocket');
      headers.set('Connection', 'Upgrade');

      // Create a new request with all the necessary information
      const doRequest = new Request(request, {
        headers,
      });

      console.log('[DEBUG] Sending request to Durable Object');
      const response = await sessionManager.fetch(doRequest as any);
      console.log('[DEBUG] Received response from Durable Object:', response.status);

      return response as any;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorStack = error instanceof Error ? error.stack : undefined;

      logger.error('WebSocket connection failed', {
        requestId,
        error: error as Error,
        context: {
          deviceId,
          errorMessage,
          errorStack,
          errorType: error?.constructor?.name,
        },
        tags: ['websocket', 'error'],
      });

      console.error('WebSocket Error Details:', {
        message: errorMessage,
        stack: errorStack,
        deviceId,
      });

      return Response.json(
        {
          ok: false,
          error: 'WebSocket connection failed',
          details: errorMessage,
        },
        { status: 500 }
      );
    }
  }

  /**
   * 获取指定设备的会话信息
   */
  static async getSessionInfo(context: MiddlewareContext): Promise<Response> {
    const { env, logger, requestId, url } = context;
    const deviceId = url.searchParams.get('device_id') ?? context.deviceId;

    if (!deviceId) {
      return Response.json(
        {
          ok: false,
          error: 'device_id is required',
        },
        { status: 400 }
      );
    }

    try {
      const sessionId = env.CICADA_SESSIONS.idFromName(deviceId);
      const sessionManager = await env.CICADA_SESSIONS.get(sessionId);
      const infoResponse = await sessionManager.fetch('http://session/info', {
        method: 'GET',
        headers: {
          'X-Device-ID': deviceId,
        },
      });

      const data = await infoResponse.json();

      return Response.json({
        ok: true,
        data,
      });
    } catch (error) {
      logger.error('Failed to fetch session info', {
        requestId,
        error: error as Error,
        context: { deviceId },
        tags: ['session', 'error'],
      });

      return Response.json(
        {
          ok: false,
          error: 'Failed to fetch session info',
        },
        { status: 500 }
      );
    }
  }
}
