/**
 * WebSocket Routes
 * Handles WebSocket connection endpoints
 */

import type { MiddlewareContext } from '../../types';
import { SessionController } from '../controllers';

/**
 * WebSocket route handler
 */
export async function handleWebSocketRoute(context: MiddlewareContext): Promise<Response> {
  try {
    console.log('[DEBUG] WebSocket route handler called');
    const result = await SessionController.handleWebSocketConnection(context);
    console.log('[DEBUG] WebSocket route handler completed', { status: result.status });
    return result;
  } catch (error) {
    console.error('[ERROR] WebSocket route handler failed:', error);
    context.logger.error('WebSocket route failed', {
      requestId: context.requestId,
      error: error as Error,
      tags: ['websocket', 'error'],
    });
    return Response.json(
      {
        ok: false,
        error: 'WebSocket route handler exception',
        details: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined,
      },
      { status: 500 }
    );
  }
}
