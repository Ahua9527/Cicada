export class NonceValidator {
  private readonly usedNonces = new Set<string>();

  constructor(private readonly maxAge: number = 300_000) {}

  validate(nonce: string, timestamp: number): boolean {
    const now = Date.now();
    if (Math.abs(now - timestamp) > this.maxAge) {
      return false;
    }

    if (this.usedNonces.has(nonce)) {
      return false;
    }

    this.usedNonces.add(nonce);
    return true;
  }

  isNonceUsed(nonce: string): boolean {
    return this.usedNonces.has(nonce);
  }

  markNonceUsed(nonce: string): void {
    this.usedNonces.add(nonce);
  }

  cleanup(maxEntries: number = 1000): void {
    if (this.usedNonces.size > maxEntries) {
      this.usedNonces.clear();
    }
  }

  clear(): void {
    this.usedNonces.clear();
  }
}

