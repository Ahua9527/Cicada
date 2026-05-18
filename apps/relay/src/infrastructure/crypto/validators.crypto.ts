/**
 * 加密验证函数
 */

/**
 * 验证时间戳是否在有效范围内
 * @param timestamp 时间戳（秒）
 * @param maxAge 最大有效期（秒）
 * @returns boolean 验证结果
 */
export function verifyTimestamp(timestamp: number, maxAge: number = 300): boolean {
  const now = Math.floor(Date.now() / 1000);
  return Math.abs(now - timestamp) <= maxAge;
}

/**
 * 验证设备ID格式
 * @param deviceId 设备ID
 * @returns boolean 验证结果
 */
export function verifyDeviceId(deviceId: string): boolean {
  if (!deviceId || typeof deviceId !== 'string') {
    return false;
  }

  // 设备ID必须为格式：MAC_[32位十六进制]
  return /^MAC_[A-F0-9]{32}$/i.test(deviceId);
}

/**
 * 验证nonce格式
 * @param nonce nonce字符串
 * @returns boolean 验证结果
 */
export function verifyNonce(nonce: string): boolean {
  if (!nonce || typeof nonce !== 'string') {
    return false;
  }

  // nonce长度必须在8-128字符之间，且只包含字母数字、连字符和下划线
  const noncePattern = /^[a-zA-Z0-9\-_.]{8,128}$/;
  return noncePattern.test(nonce);
}
