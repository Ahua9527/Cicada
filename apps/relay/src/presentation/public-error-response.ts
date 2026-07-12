const PUBLIC_ERROR_MESSAGE = 'Internal server error';

const SAFE_RESPONSE_HEADERS = [
  'Access-Control-Allow-Credentials',
  'Access-Control-Allow-Headers',
  'Access-Control-Allow-Methods',
  'Access-Control-Allow-Origin',
  'Access-Control-Expose-Headers',
  'Access-Control-Max-Age',
  'Cache-Control',
  'Content-Security-Policy',
  'Permissions-Policy',
  'Referrer-Policy',
  'Strict-Transport-Security',
  'X-Content-Type-Options',
  'X-Frame-Options',
] as const;

export function generateRequestId(): string {
  return `req_${Date.now()}_${Math.random().toString(36).slice(2, 11)}`;
}

export function createPublicServerErrorResponse(
  requestId: string,
  status = 500,
  sourceHeaders?: Headers
): Response {
  const headers = new Headers({
    'Content-Type': 'application/json',
    'X-Request-ID': requestId,
  });

  if (sourceHeaders) {
    for (const name of SAFE_RESPONSE_HEADERS) {
      const value = sourceHeaders.get(name);
      if (value !== null) {
        headers.set(name, value);
      }
    }
  }

  return new Response(
    JSON.stringify({
      ok: false,
      error: PUBLIC_ERROR_MESSAGE,
      request_id: requestId,
    }),
    { status, headers }
  );
}

export function enforcePublicServerErrorResponse(
  response: Response,
  requestId: string
): Response {
  if (response.status === 101 || response.status < 500) {
    return response;
  }

  return createPublicServerErrorResponse(requestId, response.status, response.headers);
}
