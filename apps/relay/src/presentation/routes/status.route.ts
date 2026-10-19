/**
 * Status Routes
 * Handles status query endpoints
 */

import type { MiddlewareContext } from '../../types';
import { rejectUnlessAdmin } from '../admin-auth';
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

  // 单台设备的状态需要管理员令牌；不带 device_id 的系统状态保持公开
  return rejectUnlessAdmin(context) ?? DeviceController.getDeviceStatus(context, deviceId);
}
