/**
 * Status Routes
 * Handles status query endpoints
 */

import type { MiddlewareContext } from '../../types';
import { DeviceController } from '../controllers';

/**
 * Status route handler
 */
export async function handleStatusRoute(context: MiddlewareContext): Promise<Response> {
  const url = new URL(context.request.url);
  const deviceId = url.searchParams.get('device_id');

  if (!deviceId) {
    // Return system status
    return DeviceController.getSystemStatus(context);
  }

  // Return device status
  return DeviceController.getDeviceStatus(context, deviceId);
}
