/**
 * Nonce 防重放验证器
 *
 * H10: 改为按时间淘汰——usedNonces 存储为 Map<nonce, expiry>，
 * cleanup 时删除超过窗口的旧 nonce，并按插入顺序裁剪到 maxEntries，
 * 而非全量 clear()。
 */
export class NonceValidator {
  private readonly usedNonces = new Map<string, number>();

  constructor(private readonly maxAge: number = 300_000) {}

  validate(nonce: string, timestamp: number): boolean {
    const now = Date.now();
    if (Math.abs(now - timestamp) > this.maxAge) {
      return false;
    }

    if (this.isNonceUsed(nonce)) {
      return false;
    }

    this.usedNonces.set(nonce, now + this.maxAge);
    return true;
  }

  isNonceUsed(nonce: string): boolean {
    const expiry = this.usedNonces.get(nonce);
    if (expiry === undefined) {
      return false;
    }
    if (Date.now() >= expiry) {
      this.usedNonces.delete(nonce);
      return false;
    }
    return true;
  }

  markNonceUsed(nonce: string): void {
    this.usedNonces.set(nonce, Date.now() + this.maxAge);
  }

  cleanup(maxEntries: number = 1000): void {
    const now = Date.now();
    // 1. 淘汰超过窗口的旧 nonce
    for (const [nonce, expiry] of this.usedNonces) {
      if (now >= expiry) {
        this.usedNonces.delete(nonce);
      }
    }
    // 2. 若仍超容量，按插入顺序裁剪最早的条目
    if (this.usedNonces.size > maxEntries) {
      const excess = this.usedNonces.size - maxEntries;
      let removed = 0;
      for (const nonce of this.usedNonces.keys()) {
        if (removed >= excess) {
          break;
        }
        this.usedNonces.delete(nonce);
        removed++;
      }
    }
  }

  clear(): void {
    this.usedNonces.clear();
  }
}