const SENSITIVE_ASSIGNMENT =
  /\b(authorization|api[_-]?key|password|token|secret|nonce|signature|private[_-]?key|session[_-]?secret)\s*[:=]\s*(?:Bearer\s+)?(?:"[^"]*"|'[^']*'|[^\s,;]+)/gi;

export function redactSensitiveText(value: string): string {
  return value.replace(SENSITIVE_ASSIGNMENT, '$1=[FILTERED]');
}

export function sanitizeError(error: Error): Error {
  const sanitized = new Error(redactSensitiveText(error.message));
  sanitized.name = error.name;
  sanitized.stack = error.stack ? redactSensitiveText(error.stack) : undefined;
  return sanitized;
}
