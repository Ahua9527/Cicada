/**
 * Device Routes
 * Handles device management endpoints
 */

import type { MiddlewareContext } from '../../types';
import { DeviceController } from '../controllers';

/**
 * Device list route handler
 */
export async function handleDeviceListRoute(context: MiddlewareContext): Promise<Response> {
  return DeviceController.getDeviceList(context);
}
