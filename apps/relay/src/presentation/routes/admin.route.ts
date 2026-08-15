/**
 * Admin Routes
 * 运维管理端点。默认关闭：仅在配置了 CICADA_ADMIN_TOKEN 时可用，
 * 所有请求要求 `Authorization: Bearer <token>`。
 */

import type { MiddlewareContext } from '../../types';
import { constantTimeStringEqual, isValidDeviceId } from '@cicada/shared';
import { SESSION_CONSTANTS } from '../../config/constants';
import { toDurableObjectRequest } from '../../infrastructure/cloudflare/worker-fetch-adapter';
import { createPublicServerErrorResponse } from '../public-error-response';

function readBearerToken(request: Request): string | null {
  const header = request.headers.get('Authorization');
  if (!header?.startsWith('Bearer ')) {
    return null;
  }
  return header.slice('Bearer '.length).trim() || null;
}

/**
 * POST /v1/admin/device-reset { device_id }
 * 解除设备的首见身份绑定（TOFU）——设备密钥丢失/轮换后恢复注册的唯一通道。
 */
export async function handleAdminDeviceResetRoute(context: MiddlewareContext): Promise<Response> {
  const { request, env, logger, requestId } = context;

  // 未配置令牌：端点按不存在处理，不暴露管理面的存在性。
  const adminToken = env.CICADA_ADMIN_TOKEN;
  if (!adminToken) {
    return Response.json({ ok: false, error: 'API endpoint not found' }, { status: 404 });
  }
  const bearer = readBearerToken(request);
  if (!bearer || !constantTimeStringEqual(bearer, adminToken)) {
    return Response.json(
      { ok: false, error: 'Invalid admin credentials', code: 'unauthorized' },
      { status: 401 }
    );
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
