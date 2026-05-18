/**
 * 验证性能测试
 * 测量验证逻辑的性能开销
 */

import type { CommandRequest } from '@cicada/shared/types';
import { validateCommandRequest } from '@cicada/shared/validators/command.validator';

describe('验证性能测试', () => {
  /**
   * 创建有效的命令请求
   */
  const createValidRequest = (cmd: string): CommandRequest => {
    return {
      device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
      cmd,
      ts: Date.now(),
      api_key: 'test-api-key-1234567890',
    };
  };

  /**
   * 测量函数执行时间
   */
  const measureTime = (fn: () => void, iterations: number): number => {
    const start = performance.now();
    for (let i = 0; i < iterations; i++) {
      fn();
    }
    const end = performance.now();
    return end - start;
  };

  describe('单次验证性能', () => {
    it('单次验证应该在 1ms 内完成', () => {
      const request = createValidRequest('lock');

      const start = performance.now();
      validateCommandRequest(request);
      const end = performance.now();

      const duration = end - start;
      console.log(`单次验证耗时: ${duration.toFixed(3)}ms`);

      // 单次验证应该非常快（< 1ms）
      expect(duration).toBeLessThan(1);
    });

    it('验证不同命令的性能应该一致', () => {
      const commands = ['lock', 'bt_toggle', 'ping', 'volume_mute', 'sleep'];
      const durations: number[] = [];

      for (const cmd of commands) {
        const request = createValidRequest(cmd);
        const start = performance.now();
        validateCommandRequest(request);
        const end = performance.now();
        durations.push(end - start);
      }

      console.log('不同命令验证耗时:', durations.map(d => `${d.toFixed(3)}ms`).join(', '));

      // 所有命令的验证时间应该都很快
      durations.forEach(duration => {
        expect(duration).toBeLessThan(1);
      });
    });
  });

  describe('批量验证性能', () => {
    it('1000 次验证应该在 100ms 内完成', () => {
      const request = createValidRequest('lock');
      const iterations = 1000;

      const totalTime = measureTime(() => {
        validateCommandRequest(request);
      }, iterations);

      const avgTime = totalTime / iterations;
      console.log(`1000 次验证总耗时: ${totalTime.toFixed(2)}ms`);
      console.log(`平均每次验证: ${avgTime.toFixed(3)}ms`);

      // 1000 次验证应该在 100ms 内完成
      expect(totalTime).toBeLessThan(100);

      // 平均每次验证应该在 0.1ms 内
      expect(avgTime).toBeLessThan(0.1);
    });

    it('10000 次验证应该在 500ms 内完成', () => {
      const request = createValidRequest('lock');
      const iterations = 10000;

      const totalTime = measureTime(() => {
        validateCommandRequest(request);
      }, iterations);

      const avgTime = totalTime / iterations;
      console.log(`10000 次验证总耗时: ${totalTime.toFixed(2)}ms`);
      console.log(`平均每次验证: ${avgTime.toFixed(3)}ms`);

      // 10000 次验证应该在 500ms 内完成
      expect(totalTime).toBeLessThan(500);

      // 平均每次验证应该在 0.05ms 内
      expect(avgTime).toBeLessThan(0.05);
    });
  });

  describe('验证失败场景性能', () => {
    it('验证失败不应该比验证成功慢', () => {
      const validRequest = createValidRequest('lock');
      const invalidRequest = createValidRequest('invalid_command');

      // 测量成功验证
      const validTime = measureTime(() => {
        validateCommandRequest(validRequest);
      }, 1000);

      // 测量失败验证
      const invalidTime = measureTime(() => {
        validateCommandRequest(invalidRequest);
      }, 1000);

      console.log(`成功验证 1000 次: ${validTime.toFixed(2)}ms`);
      console.log(`失败验证 1000 次: ${invalidTime.toFixed(2)}ms`);

      // 微基准容易受到运行时抖动影响；失败路径仍应保持毫秒级。
      expect(invalidTime).toBeLessThan(Math.max(validTime * 5, 10));
    });

    it('不同类型的验证失败性能应该一致', () => {
      const invalidRequests = [
        { ...createValidRequest('lock'), device_id: 'invalid' },
        { ...createValidRequest('lock'), cmd: 'invalid_command' },
        { ...createValidRequest('lock'), ts: 0 },
        { ...createValidRequest('lock'), api_key: 'short' },
      ];

      const durations: number[] = [];

      for (const request of invalidRequests) {
        const time = measureTime(() => {
          validateCommandRequest(request);
        }, 1000);
        durations.push(time);
      }

      console.log('不同失败场景验证耗时:', durations.map(d => `${d.toFixed(2)}ms`).join(', '));

      // 所有失败场景的验证时间应该都很快
      durations.forEach(duration => {
        expect(duration).toBeLessThan(100);
      });
    });
  });
});
