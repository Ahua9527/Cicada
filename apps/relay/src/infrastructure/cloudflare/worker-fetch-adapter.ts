import type {
  Request as DurableObjectRequest,
  Response as DurableObjectResponse,
} from '@cloudflare/workers-types';

/**
 * L3: Worker ↔ Durable Object 请求/响应边界转换。
 *
 * Cloudflare Workers 中 Worker 侧与 DO 侧分别使用各自的 Request/Response
 * 类型（@cloudflare/workers-types 与 DOM lib.dom.d.ts），二者结构兼容但
 * TS 视为不同类型。这里集中通过受约束的 `unknown` 桥接，避免在调用点散落
 * `as unknown as` 强转。
 */

export function toDurableObjectRequest(request: Request): DurableObjectRequest {
  // Request 结构兼容（body/headers/method/url），但 TS 类型不互通，需经 unknown 桥接。
  return request as unknown as DurableObjectRequest;
}

export function toWorkerResponse(response: DurableObjectResponse): Response {
  return response as unknown as Response;
}

export function copyDurableObjectResponse(response: DurableObjectResponse): Response {
  return new Response(response.body as unknown as BodyInit, {
    status: response.status,
    headers: response.headers as unknown as HeadersInit,
  });
}