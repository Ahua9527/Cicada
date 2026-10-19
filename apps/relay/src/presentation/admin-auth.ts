/**
 * 管理员令牌鉴权：管理端点和 /devices、/status?device_id= 共用。
 * 未配置 CICADA_ADMIN_TOKEN 时按端点不存在处理，响应与路由的 404 相同，不暴露管理面的存在性。
 */

import type { MiddlewareContext } from '../types';
import { constantTimeStringEqual } from '@cicada/shared';

function readBearerToken(request: Request): string | null {
  const header = request.headers.get('Authorization');
  if (!header?.startsWith('Bearer ')) {
    return null;
  }
  return header.slice('Bearer '.length).trim() || null;
}

/** 鉴权通过返回 null，否则返回应直接回给客户端的 404/401 响应。 */
export function rejectUnlessAdmin(context: MiddlewareContext): Response | null {
  const { request, env } = context;
  const adminToken = env.CICADA_ADMIN_TOKEN;
  if (!adminToken) {
    return Response.json(
      { ok: false, error: 'API endpoint not found', path: new URL(request.url).pathname },
      { status: 404 }
    );
  }
  const bearer = readBearerToken(request);
  if (!bearer || !constantTimeStringEqual(bearer, adminToken)) {
    return Response.json(
      { ok: false, error: 'Invalid admin credentials', code: 'unauthorized' },
      { status: 401 }
    );
  }
  return null;
}
