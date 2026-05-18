/**
 * Health Routes
 * Handles health check endpoints
 */

import type { MiddlewareContext } from '../../types';
import { DeviceController } from '../controllers';

/**
 * Health check route handler
 */
export async function handleHealthRoute(context: MiddlewareContext): Promise<Response> {
  return DeviceController.healthCheck(context);
}
