/**
 * 加密工具函数
 */

/**
 * 十六进制字符串转换为ArrayBuffer
 */
export function hexToArray(hex: string): ArrayBuffer {
  const result = new ArrayBuffer(hex.length / 2);
  const view = new Uint8Array(result);
  for (let i = 0; i < hex.length; i += 2) {
    view[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return result;
}

/**
 * 将ArrayBuffer转换为十六进制字符串
 */
export function arrayToHex(array: Uint8Array): string {
  return Array.from(array)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * 生成安全的随机nonce
 * @param length nonce长度
 * @returns string 随机nonce
 */
export function generateNonce(length: number = 32): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  let result = '';

  // 使用Web Crypto API生成随机数
  const randomValues = new Uint8Array(length);
  crypto.getRandomValues(randomValues);

  for (let i = 0; i < length; i++) {
    result += chars[randomValues[i] % chars.length];
  }

  return result;
}
