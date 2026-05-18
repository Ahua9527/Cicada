/**
 * Command Routes
 * Handles command sending endpoints
 */

import type { MiddlewareContext } from '../../types';
import { CommandController } from '../controllers';

/**
 * Send command route handler
 */
export async function handleSendCommandRoute(context: MiddlewareContext): Promise<Response> {
  return CommandController.sendCommand(context);
}
