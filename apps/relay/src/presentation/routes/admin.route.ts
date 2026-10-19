/**
 * Admin Routes
 * 运维管理端点。默认关闭：仅在配置了 CICADA_ADMIN_TOKEN 时可用，
 * 所有请求要求 `Authorization: Bearer <token>`。
 */

import type { MiddlewareContext } from '../../types';
import { isValidDeviceId } from '@cicada/shared';
import { SESSION_CONSTANTS } from '../../config/constants';
import { toDurableObjectRequest } from '../../infrastructure/cloudflare/worker-fetch-adapter';
import { rejectUnlessAdmin } from '../admin-auth';
import { createPublicServerErrorResponse } from '../public-error-response';

/**
 * POST /v1/admin/device-reset { device_id }
 * 解除设备的身份绑定——换机、重装或密钥丢失后，解绑再用新注册码登记的唯一通道。
 */
export async function handleAdminDeviceResetRoute(context: MiddlewareContext): Promise<Response> {
  const { request, env, logger, requestId } = context;

  const rejected = rejectUnlessAdmin(context);
  if (rejected) {
    return rejected;
  }

  let body: { device_id?: string };
  try {
    body = (await request.json()) as { device_id?: string };
  } catch {
    return Response.json(
      { ok: false, error: 'Request body must be JSON', code: 'invalid_body' },
      { status: 400 }
    );
  }
  const deviceId = body.device_id;
  if (!deviceId || !isValidDeviceId(deviceId)) {
    return Response.json(
      { ok: false, error: 'Valid device_id is required', code: 'invalid_device_id' },
      { status: 400 }
    );
  }

  try {
    const registryId = env.CICADA_SESSIONS.idFromName(SESSION_CONSTANTS.REGISTRY_DO_NAME);
    const registry = env.CICADA_SESSIONS.get(registryId);
    const response = await registry.fetch(
      toDurableObjectRequest(
        new Request('http://registry/registry/admin-reset-device', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-Request-ID': requestId },
          body: JSON.stringify({ deviceId }),
        })
      )
    );
    const payload = (await response.json()) as Record<string, unknown>;
    logger.info('Admin device reset', {
      requestId,
      context: { deviceId, existed: payload.existed === true },
      tags: ['admin', 'device-reset'],
    });
    return Response.json(payload, { status: response.status });
  } catch (error) {
    logger.error('Admin device reset failed', {
      requestId,
      error: error as Error,
      tags: ['admin', 'device-reset', 'error'],
    });
    return createPublicServerErrorResponse(requestId);
  }
}

/**
 * POST /v1/admin/enrollment-codes
 * 签发一次性注册码：10 分钟内有效、只能用一次，供未绑定的 deviceId 首次登记。
 * 明文只在这次响应里出现，注册表只存哈希。
 */
export async function handleAdminEnrollmentCodeRoute(
  context: MiddlewareContext
): Promise<Response> {
  const { env, logger, requestId } = context;

  const rejected = rejectUnlessAdmin(context);
  if (rejected) {
    return rejected;
  }

  try {
    const registryId = env.CICADA_SESSIONS.idFromName(SESSION_CONSTANTS.REGISTRY_DO_NAME);
    const registry = env.CICADA_SESSIONS.get(registryId);
    const response = await registry.fetch(
      toDurableObjectRequest(
        new Request('http://registry/registry/admin-enrollment-code', {
          method: 'POST',
          headers: { 'X-Request-ID': requestId },
        })
      )
    );
    const payload = (await response.json()) as Record<string, unknown>;
    // 只记状态和过期时间，明文注册码不进日志。
    logger.info('Admin enrollment code issued', {
      requestId,
      context: { status: response.status, expiresAt: payload.expiresAt },
      tags: ['admin', 'enrollment-code'],
    });
    // 明文注册码只出现这一次，不允许任何缓存保存。
    return Response.json(payload, {
      status: response.status,
      headers: { 'Cache-Control': 'no-store' },
    });
  } catch (error) {
    logger.error('Admin enrollment code issue failed', {
      requestId,
      error: error as Error,
      tags: ['admin', 'enrollment-code', 'error'],
    });
    return createPublicServerErrorResponse(requestId);
  }
}
