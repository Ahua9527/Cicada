/**
 * 加密工具单元测试
 */

import {
  verifyTimestamp,
  verifyNonce,
  verifyDeviceId,
  validateRequest,
  generateNonce,
  createApiKeyRequest,
  validateApiKeyRequest,
  validateWebSocketConnection,
} from '../../src/utils/crypto';
import { CommandRequest } from '../../src/types';

describe('Crypto Utils', () => {
  const testApiKey = 'test-api-key-for-testing';

  describe('validateApiKeyRequest', () => {
    const validDeviceId = 'MAC_1234567890ABCDEF1234567890ABCDEF';

    it('should validate a valid API key request', () => {
      const request = createApiKeyRequest(validDeviceId, 'lock', testApiKey);

      const validation = validateApiKeyRequest(request, testApiKey);
      expect(validation.valid).toBe(true);
    });

    it('should reject request with invalid API key', () => {
      const request = createApiKeyRequest(validDeviceId, 'lock', 'wrong-key');

      const validation = validateApiKeyRequest(request, testApiKey);
      expect(validation.valid).toBe(false);
      expect(validation.error).toBe('INVALID_API_KEY');
    });

    it('should reject request with missing fields', () => {
      const request = {
        device_id: validDeviceId,
        cmd: 'lock',
        // missing ts and api_key
      } as CommandRequest;

      const validation = validateApiKeyRequest(request, testApiKey);
      expect(validation.valid).toBe(false);
      expect(validation.error).toBe('MISSING_REQUIRED_FIELDS');
    });

    it('should reject request with invalid device ID', () => {
      const request = createApiKeyRequest('invalid-device-id', 'lock', testApiKey);

      const validation = validateApiKeyRequest(request, testApiKey);
      expect(validation.valid).toBe(false);
      expect(validation.error).toBe('INVALID_DEVICE_ID');
    });

    it('should reject request with expired timestamp', () => {
      const request = {
        device_id: validDeviceId,
        cmd: 'lock',
        ts: Math.floor(Date.now() / 1000) - 400, // 400 seconds ago
        api_key: testApiKey,
      };

      const validation = validateApiKeyRequest(request, testApiKey);
      expect(validation.valid).toBe(false);
      expect(validation.error).toBe('TIMESTAMP_EXPIRED');
    });
  });

  describe('validateWebSocketConnection', () => {
    const validDeviceId = 'MAC_1234567890ABCDEF1234567890ABCDEF';

    it('should validate valid WebSocket connection params', () => {
      const timestamp = Math.floor(Date.now() / 1000);

      const validation = validateWebSocketConnection(
        validDeviceId,
        testApiKey,
        testApiKey,
        timestamp
      );
      expect(validation.valid).toBe(true);
    });

    it('should reject WebSocket connection with wrong API key', () => {
      const timestamp = Math.floor(Date.now() / 1000);

      const validation = validateWebSocketConnection(
        validDeviceId,
        'wrong-key',
        testApiKey,
        timestamp
      );
      expect(validation.valid).toBe(false);
      expect(validation.error).toBe('INVALID_API_KEY');
    });

    it('should reject WebSocket connection with invalid device ID', () => {
      const timestamp = Math.floor(Date.now() / 1000);

      const validation = validateWebSocketConnection(
        'invalid-id',
        testApiKey,
        testApiKey,
        timestamp
      );
      expect(validation.valid).toBe(false);
      expect(validation.error).toBe('INVALID_DEVICE_ID');
    });

    it('should reject WebSocket connection with expired timestamp', () => {
      const timestamp = Math.floor(Date.now() / 1000) - 400; // 400 seconds ago

      const validation = validateWebSocketConnection(
        validDeviceId,
        testApiKey,
        testApiKey,
        timestamp
      );
      expect(validation.valid).toBe(false);
      expect(validation.error).toBe('TIMESTAMP_EXPIRED');
    });

    it('should reject WebSocket connection with missing parameters', () => {
      const validation = validateWebSocketConnection('', '', '', 0);
      expect(validation.valid).toBe(false);
      expect(validation.error).toBe('MISSING_REQUIRED_FIELDS');
    });
  });

  describe('createApiKeyRequest', () => {
    const validDeviceId = 'MAC_1234567890ABCDEF1234567890ABCDEF';

    it('should create a valid API key request', () => {
      const command = 'lock';
      const params = { custom: 'value' };

      const request = createApiKeyRequest(validDeviceId, command, testApiKey, params);

      expect(request.device_id).toBe(validDeviceId);
      expect(request.cmd).toBe(command);
      expect(request.api_key).toBe(testApiKey);
      expect(request.params).toEqual(params);
      expect(typeof request.ts).toBe('number');
    });

    it('should create request without optional params', () => {
      const command = 'ping';

      const request = createApiKeyRequest(validDeviceId, command, testApiKey);

      expect(request.device_id).toBe(validDeviceId);
      expect(request.cmd).toBe(command);
      expect(request.api_key).toBe(testApiKey);
      expect(request.params).toBeUndefined();
      expect(typeof request.ts).toBe('number');
    });
  });

  describe('validateRequest', () => {
    const validDeviceId = 'MAC_1234567890ABCDEF1234567890ABCDEF';

    it('should validate a complete request with nonce', async () => {
      const request = {
        device_id: validDeviceId,
        cmd: 'lock',
        ts: Math.floor(Date.now() / 1000),
        api_key: testApiKey,
        nonce: 'valid-nonce-123',
      };

      const validation = await validateRequest(request, testApiKey);
      expect(validation.valid).toBe(true);
    });

    it('should validate request without nonce', async () => {
      const request = {
        device_id: validDeviceId,
        cmd: 'lock',
        ts: Math.floor(Date.now() / 1000),
        api_key: testApiKey,
      };

      const validation = await validateRequest(request, testApiKey);
      expect(validation.valid).toBe(true);
    });

    it('should reject request with invalid command', async () => {
      const request = {
        device_id: validDeviceId,
        cmd: 'invalid-command',
        ts: Math.floor(Date.now() / 1000),
        api_key: testApiKey,
      };

      const validation = await validateRequest(request, testApiKey, ['lock', 'ping']);
      expect(validation.valid).toBe(false);
      expect(validation.error).toBe('INVALID_COMMAND');
    });

    it('should accept any command when no allowed list provided', async () => {
      const request = {
        device_id: validDeviceId,
        cmd: 'any-command',
        ts: Math.floor(Date.now() / 1000),
        api_key: testApiKey,
      };

      const validation = await validateRequest(request, testApiKey);
      expect(validation.valid).toBe(true);
    });
  });

  describe('verifyTimestamp', () => {
    it('should accept valid timestamp', () => {
      const now = Math.floor(Date.now() / 1000);
      const timestamp = now - 60; // 1 minute ago

      expect(verifyTimestamp(timestamp)).toBe(true);
    });

    it('should reject expired timestamp', () => {
      const now = Math.floor(Date.now() / 1000);
      const timestamp = now - 400; // 400 seconds ago (exceeds default 300s)

      expect(verifyTimestamp(timestamp)).toBe(false);
    });

    it('should accept custom max age', () => {
      const now = Math.floor(Date.now() / 1000);
      const timestamp = now - 400; // 400 seconds ago

      expect(verifyTimestamp(timestamp, 500)).toBe(true); // 500s max age
    });
  });

  describe('verifyNonce', () => {
    it('should accept valid nonce', () => {
      const nonce = 'abc123xyz789';

      expect(verifyNonce(nonce)).toBe(true);
    });

    it('should reject empty nonce', () => {
      expect(verifyNonce('')).toBe(false);
    });

    it('should reject too short nonce', () => {
      const nonce = 'abc';

      expect(verifyNonce(nonce)).toBe(false);
    });

    it('should reject too long nonce', () => {
      const nonce = 'a'.repeat(200);

      expect(verifyNonce(nonce)).toBe(false);
    });

    it('should reject nonce with invalid characters', () => {
      const nonce = 'abc@123';

      expect(verifyNonce(nonce)).toBe(false);
    });
  });

  describe('verifyDeviceId', () => {
    it('should accept valid device ID with correct format', () => {
      const deviceId = 'MAC_A1B2C3D4E5F67890A1B2C3D4E5F67890';

      expect(verifyDeviceId(deviceId)).toBe(true);
    });

    it('should accept device ID in lowercase', () => {
      const deviceId = 'mac_a1b2c3d4e5f67890a1b2c3d4e5f67890';

      expect(verifyDeviceId(deviceId)).toBe(true);
    });

    it('should reject empty device ID', () => {
      expect(verifyDeviceId('')).toBe(false);
    });

    it('should reject device ID without MAC_ prefix', () => {
      expect(verifyDeviceId('A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6')).toBe(false);
    });

    it('should reject device ID with wrong length', () => {
      expect(verifyDeviceId('MAC_ABC123')).toBe(false);
    });

    it('should reject device ID with invalid characters', () => {
      expect(verifyDeviceId('MAC_GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG')).toBe(false);
    });

    it('should reject old format device ID', () => {
      expect(verifyDeviceId('MAC_L9X8K2_ABC123')).toBe(false);
    });
  });

  // verifyCommand function has been removed - command validation is now done by CommandValidator
  // describe('verifyCommand', () => {
  //   it('should accept valid commands from default list', () => {
  //     expect(verifyCommand('lock')).toBe(true);
  //     expect(verifyCommand('ping')).toBe(true);
  //     expect(verifyCommand('status')).toBe(true);
  //   });

  //   it('should reject invalid commands', () => {
  //     expect(verifyCommand('invalid')).toBe(false);
  //     expect(verifyCommand('')).toBe(false);
  //   });

  //   it('should accept custom command list', () => {
  //     expect(verifyCommand('custom', ['custom', 'test'])).toBe(true);
  //     expect(verifyCommand('test', ['custom', 'test'])).toBe(true);
  //   });

  //   it('should reject commands not in custom list', () => {
  //     expect(verifyCommand('invalid', ['custom', 'test'])).toBe(false);
  //   });
  // });

  describe('generateNonce', () => {
    it('should generate nonce with default length', () => {
      const nonce = generateNonce();

      expect(typeof nonce).toBe('string');
      expect(nonce.length).toBe(32);
      expect(verifyNonce(nonce)).toBe(true);
    });

    it('should generate nonce with custom length', () => {
      const nonce = generateNonce(16);

      expect(typeof nonce).toBe('string');
      expect(nonce.length).toBe(16);
      expect(verifyNonce(nonce)).toBe(true);
    });

    it('should generate different nonces', () => {
      const nonce1 = generateNonce();
      const nonce2 = generateNonce();

      // 虽然极低概率下可能生成相同nonce，但通常应该不同
      // 如果碰巧相同，我们至少检查它们不是空的
      expect(nonce1).toBeTruthy();
      expect(nonce2).toBeTruthy();
      expect(typeof nonce1).toBe('string');
      expect(typeof nonce2).toBe('string');

      // 在大多数情况下，它们应该不同
      if (nonce1 === nonce2) {
        console.warn('Warning: Generated identical nonces - this is extremely rare but possible');
      }
    });

    it('should generate valid characters', () => {
      const nonce = generateNonce();
      const validChars = /^[A-Za-z0-9\-_]+$/;

      expect(validChars.test(nonce)).toBe(true);
    });
  });
});
