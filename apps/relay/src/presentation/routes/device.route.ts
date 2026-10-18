/**
 * Device Routes
 * Handles device management endpoints
 */

import type { MiddlewareContext } from '../../types';
import { rejectUnlessAdmin } from '../admin-auth';
import { DeviceController } from '../controllers';

/**
 * Device list route handler（需要管理员令牌）
 */
export async function handleDeviceListRoute(context: MiddlewareContext): Promise<Response> {
  return rejectUnlessAdmin(context) ?? DeviceController.getDeviceList(context);
}
