/**
 * Session Routes
 */

import type { MiddlewareContext } from '../../types';
import { SessionController } from '../controllers/session.controller';

export async function handleSessionInfoRoute(context: MiddlewareContext): Promise<Response> {
  return SessionController.getSessionInfo(context);
}
