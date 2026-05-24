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
    return await SessionController.handleWebSocketConnection(context);
  } catch (error) {
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

export async function handleShortcutCommandRoute(context: MiddlewareContext): Promise<Response> {
  return SessionController.sendShortcutCommand(context);
}
