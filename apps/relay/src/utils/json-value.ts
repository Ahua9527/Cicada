import type { JsonObject, JsonValue } from '@cicada/shared/types/common.types';

function isPlainObject(value: object): value is Record<string, unknown> {
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

export function isJsonValue(value: unknown, ancestors: ReadonlySet<object> = new Set()): value is JsonValue {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') {
    return true;
  }
  if (typeof value === 'number') {
    return Number.isFinite(value);
  }
  if (typeof value !== 'object' || ancestors.has(value)) {
    return false;
  }

  const nextAncestors = new Set(ancestors).add(value);
  if (Array.isArray(value)) {
    return value.every(item => isJsonValue(item, nextAncestors));
  }
  if (!isPlainObject(value)) {
    return false;
  }
  return Object.values(value).every(item => isJsonValue(item, nextAncestors));
}

export function requireJsonValue(value: unknown, label: string): JsonValue {
  if (!isJsonValue(value)) {
    throw new TypeError(`${label} must contain only JSON-compatible values`);
  }
  return value;
}

export function requireJsonObject(
  value: Record<string, unknown> | undefined,
  label: string
): JsonObject | undefined {
  if (value === undefined) {
    return undefined;
  }
  const jsonValue = requireJsonValue(value, label);
  if (Array.isArray(jsonValue) || jsonValue === null || typeof jsonValue !== 'object') {
    throw new TypeError(`${label} must be a JSON object`);
  }
  return jsonValue;
}
