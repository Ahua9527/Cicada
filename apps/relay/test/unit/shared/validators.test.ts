import { NonceValidator } from '@cicada/shared/validators/nonce.validator';
import { SessionValidator } from '@cicada/shared/validators/session.validator';

describe('shared validators', () => {
  describe('NonceValidator', () => {
    beforeEach(() => jest.spyOn(Date, 'now').mockReturnValue(10_000));

    it('accepts a fresh nonce and rejects stale or replayed values', () => {
      const validator = new NonceValidator(1_000);

      expect(validator.validate('fresh', 10_000)).toBe(true);
      expect(validator.validate('fresh', 10_000)).toBe(false);
      expect(validator.validate('old', 8_999)).toBe(false);
    });

    it('retains future-dated nonces through their full validity window', () => {
      const validator = new NonceValidator(1_000);
      const dateNowSpy = jest.spyOn(Date, 'now');

      // now=10_000，时间戳取窗口尽头 11_000：接受并记录
      expect(validator.validate('future', 11_000)).toBe(true);

      // 时间推进到原"首次使用锚定"的过期点 11_000：该时间戳仍然合法，
      // nonce 必须仍被标记为已使用（重放拒绝）
      dateNowSpy.mockReturnValue(11_000);
      expect(validator.validate('future', 11_000)).toBe(false);
      expect(validator.isNonceUsed('future')).toBe(true);

      // 时间戳窗口真正结束后（>12_000），条目才可过期
      dateNowSpy.mockReturnValue(12_001);
      expect(validator.isNonceUsed('future')).toBe(false);
      expect(validator.validate('future', 11_000)).toBe(false); // 时间戳已 stale
    });

    it('supports explicit marking, bounded cleanup, and clearing', () => {
      const validator = new NonceValidator();
      validator.markNonceUsed('one');
      validator.cleanup(1);
      expect(validator.isNonceUsed('one')).toBe(true);

      validator.markNonceUsed('two');
      validator.cleanup(1);
      expect(validator.isNonceUsed('one')).toBe(false);

      validator.markNonceUsed('three');
      validator.clear();
      expect(validator.isNonceUsed('three')).toBe(false);
    });
  });

  describe('SessionValidator', () => {
    it('accepts omitted optional timestamps', () => {
      expect(
        new SessionValidator().validate({
          sessionId: null,
          isActive: false,
          createdAt: null,
          lastActivity: null,
        })
      ).toBe(true);
    });

    it('reports every invalid optional field', () => {
      const validator = new SessionValidator();

      expect(
        validator.validate({
          sessionId: 'short',
          isActive: true,
          createdAt: -1,
          lastActivity: -1,
          connectedAt: -1,
          lastPing: -1,
        })
      ).toBe(false);
      expect(validator.getErrors()).toHaveLength(5);
    });
  });
});
