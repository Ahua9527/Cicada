/**
 * Nonce 防重放验证器
 *
 * H10: 改为按时间淘汰——usedNonces 存储为 Map<nonce, expiry>，
 * cleanup 时删除超过窗口的旧 nonce，并按插入顺序裁剪到 maxEntries，
 * 而非全量 clear()。
 *
 * 过期时刻锚定到所声明时间戳的最晚可接受时间（timestamp + maxAge），
 * 而非首次使用时刻：时间戳采用 ±maxAge 对称窗口，未来时间戳在该窗口
 * 内一直合法，若按 now + maxAge 过期会留下最长一个 maxAge 的重放窗口。
 * 条目保留到该边界之后才淘汰（> 而非 >=）：边界处时间戳仍合法，nonce
 * 须仍标记已用，否则捕获的请求能在 timestamp + maxAge 精确重放。
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

    this.usedNonces.set(nonce, timestamp + this.maxAge);
    return true;
  }

  isNonceUsed(nonce: string): boolean {
    const expiry = this.usedNonces.get(nonce);
    if (expiry === undefined) {
      return false;
    }
    if (Date.now() > expiry) {
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
    // 1. 淘汰窗口之外的旧 nonce（> 而非 >=：边界处时间戳仍合法，须保留到边界之后）
    for (const [nonce, expiry] of this.usedNonces) {
      if (now > expiry) {
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