import type {
  Request as DurableObjectRequest,
  Response as DurableObjectResponse,
} from '@cloudflare/workers-types';

export function toDurableObjectRequest(request: unknown): DurableObjectRequest {
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
