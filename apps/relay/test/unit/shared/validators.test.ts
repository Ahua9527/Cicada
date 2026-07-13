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
