#!/usr/bin/env node

/**
 * CicadaRelay 调试工具集
 *
 * 提供签名生成、数据模拟、WebSocket测试等功能
 */

import { createHash } from 'crypto';
import { WebSocket } from 'ws';

// 配置
const CONFIG = {
  API_KEY: process.env.API_KEY || 'dev-debug-key-12345678901234567890',
  DEFAULT_DEVICE_ID: 'debug-device-001',
  COLORS: {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    magenta: '\x1b[35m',
    cyan: '\x1b[36m'
  }
};

/**
 * 彩色输出工具
 */
function colorLog(message, color = 'white') {
  const colorCode = CONFIG.COLORS[color] || CONFIG.COLORS.reset;
  console.log(`${colorCode}${message}${CONFIG.COLORS.reset}`);
}

function colorLogJson(obj, title, color = 'white') {
  colorLog(`\n[列表] ${title}:`, color);
  console.log(JSON.stringify(obj, null, 2));
}

/**
 * API Key 认证工具
 */
class ApiKeyGenerator {
  constructor() {
    this.apiKey = CONFIG.API_KEY;
  }

  /**
   * 创建API Key请求
   */
  createRequest(deviceId, command, params = {}) {
    const timestamp = Math.floor(Date.now() / 1000);

    return {
      device_id: deviceId,
      cmd: command,
      ts: timestamp,
      api_key: this.apiKey,
      params
    };
  }

  /**
   * 创建WebSocket连接参数
   */
  createWebSocketParams(deviceId) {
    const timestamp = Math.floor(Date.now() / 1000);

    return {
      device_id: deviceId,
      api_key: this.apiKey,
      ts: timestamp
    };
  }

  /**
   * 生成时间戳
   */
  getTimestamp() {
    return Math.floor(Date.now() / 1000);
  }

  /**
   * 生成随机nonce
   */
  generateNonce(length = 32) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
    let result = '';
    for (let i = 0; i < length; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }

  /**
   * 创建命令请求签名
   */
  createCommandRequest(deviceId, command, params = {}) {
    const timestamp = this.getTimestamp();
    const nonce = this.generateNonce();
    const payload = `${deviceId}:${command}:${timestamp}:${nonce}`;
    const signature = this.generateSignature(payload);

    const request = {
      device_id: deviceId,
      cmd: command,
      ts: timestamp,
      nonce,
      sig: signature,
      ...params
    };

    // 验证签名
    const isValid = this.verifySignature(payload, signature);
    if (!isValid) {
      throw new Error('签名验证失败');
    }

    return request;
  }

  /**
   * 创建WebSocket连接签名
   */
  createWebSocketSignature(deviceId) {
    const timestamp = this.getTimestamp();
    const nonce = this.generateNonce();
    const payload = `${deviceId}:connect:${timestamp}:${nonce}`;
    const signature = this.generateSignature(payload);

    return {
      device_id: deviceId,
      sig: signature,
      ts: timestamp,
      nonce
    };
  }

  /**
   * 生成签名测试数据
   */
  generateTestData() {
    const testData = {
      deviceId: CONFIG.DEFAULT_DEVICE_ID,
      commands: ['ping', 'status', 'lock', 'bt_on', 'bt_off', 'sleep_hold', 'sleep_release'],
      results: []
    };

    colorLog('\n[安全] 签名生成测试', 'cyan');
    colorLog('=' .repeat(50), 'cyan');
    colorLog(`使用密钥: ${this.key.substring(0, 20)}...`, 'yellow');

    for (const command of testData.commands) {
      try {
        const request = this.createCommandRequest(testData.deviceId, command);
        testData.results.push({
          command,
          success: true,
          request
        });

        colorLog(`[成功] ${command}: 签名生成成功`, 'green');
        colorLog(`   签名: ${request.sig.substring(0, 20)}...`, 'blue');
        colorLog(`   Nonce: ${request.nonce}`, 'blue');
        colorLog(`   时间戳: ${request.ts}`, 'blue');
        colorLog('', 'gray');

        // 验证签名
        const payload = `${testData.deviceId}:${command}:${request.ts}:${request.nonce}`;
        const isValid = this.verifySignature(payload, request.sig);
        if (!isValid) {
          throw new Error(`签名验证失败: ${command}`);
        }

      } catch (error) {
        colorLog(`[错误] ${command}: ${error.message}`, 'red');
        testData.results.push({
          command,
          success: false,
          error: error.message
        });
      }
    }

    const successCount = testData.results.filter(r => r.success).length;
    const totalCount = testData.results.length;

    colorLog(`\n[统计] 测试结果: ${successCount}/${totalCount} 成功`,
      successCount === totalCount ? 'green' : 'yellow');

    return testData;
  }
}

/**
 * WebSocket测试工具
 */
class WebSocketTester {
  constructor(baseUrl = 'http://localhost:8787') {
    this.baseUrl = baseUrl;
    this.wsUrl = baseUrl.replace('http', 'ws');
    this.connections = new Map();
  }

  /**
   * 测试WebSocket连接
   */
  async testConnection(deviceId, signature) {
    colorLog('\n[连接] WebSocket连接测试', 'magenta');
    colorLog('=' .repeat(50), 'magenta');

    if (!signature) {
      const generator = new SignatureGenerator();
      signature = generator.createWebSocketSignature(deviceId);
    }

    colorLog('[列表] 连接参数:', 'yellow');
    colorLogJson(signature, 'WebSocket连接参数', 'yellow');

    const wsParams = new URLSearchParams(signature).toString();
    const wsEndpoint = `${this.wsUrl}/ws?${wsParams}`;

    colorLog(`\n[链接] WebSocket URL: ${wsEndpoint}`, 'blue');

    return new Promise((resolve, reject) => {
      const ws = new WebSocket(wsEndpoint);
      const startTime = Date.now();
      let messageCount = 0;
      const testMessages = [
        { type: 'ping', timestamp: Date.now() },
        { type: 'echo', data: 'test message', timestamp: Date.now() },
        { type: 'status', timestamp: Date.now() }
      ];

      const timeout = setTimeout(() => {
        ws.close();
        reject(new Error('WebSocket连接超时'));
      }, 15000);

      ws.on('open', () => {
        const connectTime = Date.now() - startTime;
        colorLog(`[成功] WebSocket连接成功 (耗时: ${connectTime}ms)`, 'green');

        // 发送测试消息
        testMessages.forEach((message, index) => {
          setTimeout(() => {
            ws.send(JSON.stringify(message));
            colorLog(`📤 发送消息 #${index + 1}: ${message.type}`, 'blue');
          }, index * 1000);
        });
      });

      ws.on('message', (data) => {
        try {
          const message = JSON.parse(data);
          messageCount++;
          const receiveTime = Date.now() - startTime;

          colorLog(`📨 收到消息 #${messageCount} (耗时: ${receiveTime}ms):`, 'green');
          colorLogJson(message, '消息内容', 'blue');

          if (messageCount >= testMessages.length) {
            clearTimeout(timeout);
            ws.close();
            resolve({
              success: true,
              messageCount,
              totalDuration: Date.now() - startTime,
              messagesPerSecond: (messageCount / (Date.now() - startTime)) * 1000
            });
          }
        } catch (error) {
          colorLog(`[错误] 消息解析失败: ${error.message}`, 'red');
        }
      });

      ws.on('error', (error) => {
        clearTimeout(timeout);
        colorLog('[错误] WebSocket错误', 'red');
        colorLog(error.message, 'red');
        reject(error);
      });

      ws.on('close', (code, reason) => {
        clearTimeout(timeout);
        if (messageCount > 0) {
          resolve({
            success: true,
            messageCount,
            closeCode: code,
            closeReason: reason,
            totalDuration: Date.now() - startTime
          });
        } else {
          reject(new Error(`WebSocket连接关闭: ${code} ${reason}`));
        }
      });
    });
  }

  /**
   * 测试WebSocket重连
   */
  async testReconnection(deviceId, signature, maxReconnects = 3) {
    colorLog('\n[会话] WebSocket重连测试', 'cyan');
    colorLog('=' .repeat(50), 'cyan');
    colorLog(`最大重连次数: ${maxReconnects}`, 'yellow');

    let attempt = 0;
    let lastError = null;

    while (attempt < maxReconnects) {
      attempt++;
      colorLog(`\n[链接] 尝试连接 #${attempt}`, 'blue');

      try {
        const result = await this.testConnection(deviceId, signature);
        colorLog(`[成功] 重连成功 (尝试 #${attempt})`, 'green');
        return {
          success: true,
          attempt,
          result
        };
      } catch (error) {
        lastError = error;
        colorLog(`[错误] 连接失败 (尝试 #${attempt}): ${error.message}`, 'red');

        if (attempt < maxReconnects) {
          colorLog(`⏳ 等待 2 秒后重试...`, 'yellow');
          await new Promise(resolve => setTimeout(resolve, 2000));
        }
      }
    }

    return {
      success: false,
      attempt,
      error: lastError
    };
  }

  /**
   * 测试并发连接
   */
  async testConcurrentConnections(deviceId, signature, concurrentCount = 5) {
    colorLog('\n[性能] WebSocket并发连接测试', 'blue');
    colorLog('=' .repeat(50), 'blue');
    colorLog(`并发连接数: ${concurrentCount}`, 'yellow');

    const promises = [];
    const startTime = Date.now();

    for (let i = 0; i < concurrentCount; i++) {
      const testDeviceId = `${deviceId}-concurrent-${i}`;
      promises.push(this.testConnection(testDeviceId, signature));
    }

    try {
      const results = await Promise.allSettled(promises);
      const endTime = Date.now();
      const duration = endTime - startTime;

      const successful = results.filter(r => r.status === 'fulfilled').length;
      const failed = results.filter(r => r.status === 'rejected').length;

      colorLog(`\n[统计] 并发测试结果:`, 'cyan');
      colorLog(`总连接数: ${concurrentCount}`, 'blue');
      colorLog(`成功连接: ${successful}`, 'green');
      colorLog(`连接失败: ${failed}`, failed > 0 ? 'red' : 'green');
      colorLog(`总耗时: ${duration}ms`, 'yellow');

      if (successful === concurrentCount) {
        colorLog(`[完成] 所有连接都成功！`, 'bright');
      }

      return {
        total: concurrentCount,
        successful,
        failed,
        duration,
        averageDuration: duration / concurrentCount
      };
    } catch (error) {
      colorLog(`[崩溃] 并发测试失败: ${error.message}`, 'red');
      throw error;
    }
  }
}

/**
 * 数据生成器
 */
class DataGenerator {
  constructor() {
    this.devices = [];
    this.commands = ['lock', 'bt_on', 'bt_off', 'sleep_hold', 'sleep_release', 'ping', 'status'];
    this.statuses = ['connected', 'disconnected', 'connecting', 'error'];
  }

  /**
   * 生成模拟设备数据
   */
  generateMockDevices(count = 5) {
    colorLog('\n[设备] 生成模拟设备数据', 'yellow');
    colorLog('=' .repeat(50), 'yellow');
    colorLog(`设备数量: ${count}`, 'blue');

    const devices = [];

    for (let i = 0; i < count; i++) {
      const device = {
        deviceId: `mock-device-${String(i + 1).padStart(3, '0')}`,
        name: `Mock Device ${i + 1}`,
        model: `MacBook Pro ${i + 1}`,
        osVersion: `macOS ${14}.${Math.floor(Math.random() * 5)}.${Math.floor(Math.random() * 10)}`,
        appVersion: '1.0.0',
        capabilities: this.generateCapabilities(),
        lastSeen: Date.now() - Math.random() * 3600000, // 最近1小时内
        firstSeen: Date.now() - Math.random() * 86400000, // 最近24小时内
        status: this.statuses[Math.floor(Math.random() * this.statuses.length)],
        ipAddress: this.generateIPAddress(),
        userAgent: 'Cicada/1.0.0',
        messagesExchanged: Math.floor(Math.random() * 100),
        uptime: Math.floor(Math.random() * 3600000) // 0-1小时
      };

      devices.push(device);
      colorLog(`[成功] 生成设备: ${device.deviceId} - ${device.name}`, 'green');
    }

    this.devices = devices;
    return devices;
  }

  /**
   * 生成设备能力
   */
  generateCapabilities() {
    const allCapabilities = ['lock_screen', 'bluetooth_control', 'sleep_control', 'system_info'];
    const capabilities = [];

    // 随机选择2-4个能力
    const capabilityCount = Math.floor(Math.random() * 3) + 2;
    const shuffled = allCapabilities.sort(() => 0.5 - Math.random());

    for (let i = 0; i < capabilityCount; i++) {
      capabilities.push(shuffled[i]);
    }

    return capabilities;
  }

  /**
   * 生成IP地址
   */
  generateIPAddress() {
    const octets = [];
    for (let i = 0; i < 4; i++) {
      octets.push(Math.floor(Math.random() * 256));
    }
    return `${octets[0]}.${octets[1]}.${octets[2]}.${octets[3]}`;
  }

  /**
   * 生成模拟命令历史
   */
  generateCommandHistory(deviceCount = 3, commandsPerDevice = 10) {
    colorLog('\n📜 生成模拟命令历史', 'cyan');
    colorLog('=' .repeat(50), 'cyan');
    colorLog(`设备数量: ${deviceCount}, 每设备命令数: ${commandsPerDevice}`, 'blue');

    const history = [];

    for (let deviceIndex = 0; deviceIndex < deviceCount; deviceIndex++) {
      const deviceId = `mock-device-${String(deviceIndex + 1).padStart(3, '0')}`;
      const deviceHistory = [];

      for (let cmdIndex = 0; cmdIndex < commandsPerDevice; cmdIndex++) {
        const command = {
          deviceId,
          command: this.commands[Math.floor(Math.random() * this.commands.length)],
          timestamp: Date.now() - Math.random() * 3600000, // 最近1小时内
          nonce: this.generateNonce(),
          success: Math.random() > 0.1, // 90%成功率
          duration: Math.floor(Math.random() * 1000) + 100 // 100-1100ms
        };

        deviceHistory.push(command);
      }

      history.push(...deviceHistory);
      colorLog(`[设备] 设备 ${deviceId}: ${deviceHistory.length} 个命令`, 'green');
    }

    return history;
  }

  /**
   * 生成测试数据集合
   */
  generateTestDataset() {
    const dataset = {
      devices: this.generateMockDevices(),
      commandHistory: this.generateCommandHistory(),
      statistics: {
        totalDevices: this.devices.length,
        totalCommands: 0,
        successRate: 0,
        averageLatency: 0,
        devicesByStatus: {}
      }
    };

    // 计算统计信息
    dataset.commandHistory.forEach(cmd => {
      dataset.statistics.totalCommands++;
      if (cmd.success) {
        dataset.statistics.successRate += (1 / dataset.statistics.totalCommands);
      }
      dataset.statistics.averageLatency += cmd.duration;
    });

    dataset.statistics.averageLatency = Math.floor(dataset.statistics.averageLatency / dataset.statistics.totalCommands);

    // 按状态统计设备
    this.devices.forEach(device => {
      dataset.statistics.devicesByStatus[device.status] = (dataset.statistics.devicesByStatus[device.status] || 0) + 1;
    });

    colorLog('\n[统计] 测试数据集统计:', 'bright');
    colorLogJson(dataset.statistics, '数据统计', 'yellow');

    return dataset;
  }

  /**
   * 生成随机nonce
   */
  generateNonce(length = 32) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
    let result = '';
    for (let i = 0; i < length; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }
}

/**
 * 性能测试工具
 */
class PerformanceTester {
  constructor() {
    this.results = [];
  }

  /**
   * 测试API响应时间
   */
  async testAPIResponseTime(url, requestCount = 100) {
    colorLog('\n[性能] API响应时间测试', 'blue');
    colorLog('=' .repeat(50), 'blue');
    colorLog(`测试URL: ${url}`, 'yellow');
    colorLog(`请求次数: ${requestCount}`, 'yellow');

    const results = [];
    const startTime = Date.now();

    for (let i = 0; i < requestCount; i++) {
      const requestStart = Date.now();

      try {
        const response = await fetch(url, {
          method: 'GET',
          headers: { 'User-Agent': 'CicadaRelay-Performance-Tester/1.0.0' }
        });

        const requestEnd = Date.now();
        const duration = requestEnd - requestStart;

        results.push({
          requestNumber: i + 1,
          duration,
          success: true,
          status: response.status,
          timestamp: requestStart
        });

        if ((i + 1) % 20 === 0) {
          colorLog(`[统计] 已完成 ${i + 1}/${requestCount} 个请求`, 'cyan');
        }

      } catch (error) {
        const requestEnd = Date.now();
        const duration = requestEnd - requestStart;

        results.push({
          requestNumber: i + 1,
          duration,
          success: false,
          error: error.message,
          timestamp: requestStart
        });

        colorLog(`[错误] 请求 #${i + 1} 失败: ${error.message}`, 'red');
      }
    }

    const endTime = Date.now();
    const totalTime = endTime - startTime;

    this.analyzePerformanceResults(results, totalTime);
  }

  /**
   * 分析性能结果
   */
  analyzePerformanceResults(results, totalTime) {
    const successful = results.filter(r => r.success);
    const failed = results.filter(r => !r.success);

    const durations = successful.map(r => r.duration);
    const minDuration = Math.min(...durations);
    const maxDuration = Math.max(...durations);
    const avgDuration = durations.reduce((a, b) => a + b, 0) / durations.length;

    const requestsPerSecond = (results.length / totalTime) * 1000;

    colorLog('\n[统计] 性能测试结果', 'bright');
    colorLog('=' .repeat(50), 'bright');
    colorLog(`总请求数: ${results.length}`, 'blue');
    colorLog(`成功请求: ${successful.length}`, 'green');
    colorLog(`失败请求: ${failed.length}`, failed.length > 0 ? 'red' : 'green');
    colorLog(`成功率: ${((successful.length / results.length) * 100).toFixed(2)}%`,
      successful.length === results.length ? 'green' : 'yellow');
    colorLog(`总耗时: ${totalTime}ms`, 'blue');
    colorLog(`请求速率: ${requestsPerSecond.toFixed(2)} req/s`, 'cyan');

    colorLog('\n[计时] 响应时间统计:', 'yellow');
    colorLog(`最短响应时间: ${minDuration}ms`, 'green');
    colorLog(`最长响应时间: ${maxDuration}ms`, failed.length > 0 ? 'red' : 'yellow');
    colorLog(`平均响应时间: ${avgDuration.toFixed(2)}ms`, 'blue');

    // 保存结果
    this.results.push({
      testType: 'API响应时间',
      timestamp: Date.now(),
      totalRequests: results.length,
      successfulRequests: successful.length,
      failedRequests: failed.length,
      successRate: (successful.length / results.length) * 100,
      averageLatency: avgDuration,
      minLatency: minDuration,
      maxLatency: maxDuration,
      requestsPerSecond,
      totalTime
    });

    return this.results[this.results.length - 1];
  }
}

/**
 * 命令行接口
 */
async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    // 显示帮助信息
    colorLog('\n[工具] CicadaRelay调试工具集', 'bright');
    colorLog('=' .repeat(50), 'bright');
    colorLog('\n使用方法:', 'yellow');
    colorLog('  node debug-tools.js [工具] [参数]', 'white');
    colorLog('\n可用工具:', 'yellow');
    colorLog('  signature          - 签名生成测试', 'white');
    colorLog('  websocket          - WebSocket连接测试', 'width: 16');
    colorLog('  websocket:reconnect - WebSocket重连测试', 'width: 16');
    colorLog('  websocket:concurrent - WebSocket并发测试', 'width: 16');
    colorLog('  data               - 生成测试数据', 'white');
    colorLog('  performance        - API性能测试', 'white');
    colorLog('\n示例:', 'cyan');
    colorLog('  node debug-tools.js signature', 'white');
    colorLog('  node debug-tools.js websocket ws-device-001', 'white');
    colorLog('  node debug-tools.js data 5', 'white');
    colorLog('  node debug-tools.js performance 100', 'white');

    process.exit(0);
  }

  const tool = args[0];
  const toolArgs = args.slice(1);

  try {
    switch (tool) {
      case 'signature': {
        const generator = new SignatureGenerator();
        generator.generateTestData();
        break;
      }

      case 'websocket': {
        const tester = new WebSocketTester();
        const deviceId = toolArgs[0] || CONFIG.DEFAULT_DEVICE_ID;
        await tester.testConnection(deviceId);
        break;
      }

      case 'websocket:reconnect': {
        const tester = new WebSocketTester();
        const deviceId = toolArgs[0] || CONFIG.DEFAULT_DEVICE_ID;
        const maxReconnects = parseInt(toolArgs[1]) || 3;
        await tester.testReconnection(deviceId, null, maxReconnects);
        break;
      }

      case 'websocket:concurrent': {
        const tester = new WebSocketTester();
        const deviceId = toolArgs[0] || CONFIG.DEFAULT_DEVICE_ID;
        const concurrentCount = parseInt(toolArgs[1]) || 5;
        await tester.testConcurrentConnections(deviceId, null, concurrentCount);
        break;
      }

      case 'data': {
        const generator = new DataGenerator();
        const deviceCount = parseInt(toolArgs[0]) || 5;
        const dataset = generator.generateTestDataset();
        colorLog('\n[许可] 测试数据已生成完成，可以用于开发和测试', 'green');
        break;
      }

      case 'performance': {
        const tester = new PerformanceTester();
        const requestCount = parseInt(toolArgs[0]) || 100;
        const baseUrl = toolArgs[1] || 'http://localhost:8787';
        await tester.testAPIResponseTime(`${baseUrl}/health`, requestCount);
        break;
      }

      default:
        colorLog(`[错误] 未知工具: ${tool}`, 'red');
        colorLog('运行 "node debug-tools.js" 查看帮助', 'yellow');
        process.exit(1);
    }
  } catch (error) {
    colorLog(`[崩溃] 工具执行失败: ${error.message}`, 'red');
      colorLog(error.stack, 'red');
      process.exit(1);
    }
}

// 运行主程序
main().catch(error => {
  colorLog(`[崩溃] 程序执行失败: ${error.message}`, 'red');
  process.exit(1);
});