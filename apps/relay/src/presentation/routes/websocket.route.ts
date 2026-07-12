/**
 * WebSocket Routes
 * Handles WebSocket connection endpoints
 */

import type { MiddlewareContext } from '../../types';
import { SessionController } from '../controllers';
import { createPublicServerErrorResponse } from '../public-error-response';

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
    return createPublicServerErrorResponse(context.requestId);
  }
}

export async function handleShortcutCommandRoute(context: MiddlewareContext): Promise<Response> {
  return SessionController.sendShortcutCommand(context);
}
