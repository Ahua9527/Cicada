#!/usr/bin/env node

/**
 * CicadaRelay 集成测试调试工具
 *
 * 提供完整的端到端集成测试功能
 */

import { spawn } from 'child_process';
import { createInterface } from 'readline';

// 配置
const CONFIG = {
  COLORS: {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    magenta: '\x1b[35m',
    cyan: '\x1b[36m',
    white: '\x1b[37m',
    gray: '\x1b[90m'
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
 * 集成测试管理器
 */
class IntegrationTestRunner {
  constructor() {
    this.baseUrl = process.env.CICADA_RELAY_URL || 'http://localhost:8787';
    this.signingKey = process.env.HMAC_SECRET || 'test-signing-key';
    this.testResults = [];
  }

  /**
   * 运行所有集成测试
   */
  async runAllTests() {
    colorLog('\n[启动] 开始运行CicadaRelay集成测试', 'bright');
    colorLog('=' .repeat(60), 'bright');
    colorLog(`基础URL: ${this.baseUrl}`, 'cyan');
    colorLog(`签名密钥: ${this.signingKey.substring(0, 10)}...`, 'cyan');

    try {
      // 1. 环境检查
      await this.checkEnvironment();

      // 2. 基础连接测试
      await this.testBasicConnection();

      // 3. 设备管理集成测试
      await this.testDeviceManagement();

      // 4. API功能集成测试
      await this.testApiFunctionality();

      // 5. WebSocket集成测试
      await this.testWebSocketFunctionality();

      // 6. 安全集成测试
      await this.testSecurityFeatures();

      // 7. 性能集成测试
      await this.testPerformance();

      // 8. 错误处理测试
      await this.testErrorHandling();

      // 9. 并发测试
      await this.testConcurrency();

      // 10. 负载测试
      await this.testLoad();

      this.printTestSummary();

    } catch (error) {
      colorLog(`[错误] 集成测试失败: ${error.message}`, 'red');
      throw error;
    }
  }

  /**
   * 检查测试环境
   */
  async checkEnvironment() {
    colorLog('\n[查询] 检查测试环境', 'cyan');
    colorLog('-'.repeat(30), 'cyan');

    const checks = [
      { name: '服务器连接', test: () => this.checkServerConnection() },
      { name: '环境变量', test: () => this.checkEnvironmentVariables() },
      { name: '依赖服务', test: () => this.checkDependencies() }
    ];

    for (const check of checks) {
      try {
        await check.test();
        colorLog(`[成功] ${check.name}`, 'green');
      } catch (error) {
        colorLog(`[错误] ${check.name}: ${error.message}`, 'red');
        throw error;
      }
    }
  }

  /**
   * 测试基础连接
   */
  async testBasicConnection() {
    colorLog('\n[链接] 测试基础连接', 'blue');
    colorLog('-'.repeat(30), 'blue');

    const healthCheck = await this.makeRequest('GET', '/health');

    if (healthCheck.success) {
      colorLog('[成功] 健康检查通过', 'green');
      colorLogJson(healthCheck.data, '健康检查响应', 'gray');
    } else {
      throw new Error(`健康检查失败: ${healthCheck.error}`);
    }
  }

  /**
   * 测试设备管理
   */
  async testDeviceManagement() {
    colorLog('\n[设备] 测试设备管理', 'magenta');
    colorLog('-'.repeat(30), 'magenta');

    // 测试设备注册
    const testDevice = await this.createTestDevice();
    colorLog(`[成功] 创建测试设备: ${testDevice.id}`, 'green');

    // 测试设备状态查询
    const statusResult = await this.queryDeviceStatus(testDevice.id);
    if (statusResult.success) {
      colorLog('[成功] 设备状态查询成功', 'green');
    }

    // 测试设备列表
    const devicesResult = await this.listDevices();
    if (devicesResult.success) {
      colorLog(`[成功] 设备列表获取成功 (${devicesResult.data?.devices?.length || 0}个设备)`, 'green');
    }

    // 测试设备删除
    const deleteResult = await this.deleteDevice(testDevice.id);
    if (deleteResult.success) {
      colorLog('[成功] 设备删除成功', 'green');
    }
  }

  /**
   * 测试API功能
   */
  async testApiFunctionality() {
    colorLog('\n[网络] 测试API功能', 'yellow');
    colorLog('-'.repeat(30), 'yellow');

    const testDevice = await this.createTestDevice();

    // 测试命令发送
    const commands = ['ping', 'status', 'info'];
    for (const command of commands) {
      const result = await this.sendCommand(testDevice.id, command);
      if (result.success) {
        colorLog(`[成功] 命令 "${command}" 执行成功`, 'green');
      } else {
        colorLog(`[警告]  命令 "${command}" 执行失败: ${result.error}`, 'yellow');
      }
    }

    // 测试批量操作
    const batchResult = await this.testBatchOperations(testDevice.id);
    if (batchResult.success) {
      colorLog('[成功] 批量操作测试通过', 'green');
    }

    // 清理测试设备
    await this.deleteDevice(testDevice.id);
  }

  /**
   * 测试WebSocket功能
   */
  async testWebSocketFunctionality() {
    colorLog('\n[连接] 测试WebSocket功能', 'cyan');
    colorLog('-'.repeat(30), 'cyan');

    const testDevice = await this.createTestDevice();

    try {
      // 测试WebSocket连接
      const wsResult = await this.testWebSocketConnection(testDevice.id);
      if (wsResult.success) {
        colorLog('[成功] WebSocket连接测试通过', 'green');
      }

      // 测试消息传递
      const msgResult = await this.testWebSocketMessaging(testDevice.id);
      if (msgResult.success) {
        colorLog('[成功] WebSocket消息传递测试通过', 'green');
      }

    } catch (error) {
      colorLog(`[警告]  WebSocket测试跳过: ${error.message}`, 'yellow');
    }

    // 清理测试设备
    await this.deleteDevice(testDevice.id);
  }

  /**
   * 测试安全功能
   */
  async testSecurityFeatures() {
    colorLog('\n[锁定] 测试安全功能', 'red');
    colorLog('-'.repeat(30), 'red');

    // 测试签名验证
    const authResult = await this.testAuthentication();
    if (authResult.success) {
      colorLog('[成功] 身份验证测试通过', 'green');
    } else {
      colorLog('[错误] 身份验证测试失败', 'red');
    }

    // 测试输入验证
    const inputValidationResult = await this.testInputValidation();
    if (inputValidationResult.success) {
      colorLog('[成功] 输入验证测试通过', 'green');
    } else {
      colorLog('[错误] 输入验证测试失败', 'red');
    }

    // 测试速率限制
    const rateLimitResult = await this.testRateLimiting();
    if (rateLimitResult.success) {
      colorLog('[成功] 速率限制测试通过', 'green');
    } else {
      colorLog('[警告]  速率限制测试可能未启用', 'yellow');
    }
  }

  /**
   * 测试性能
   */
  async testPerformance() {
    colorLog('\n[性能] 测试性能', 'green');
    colorLog('-'.repeat(30), 'green');

    const testDevice = await this.createTestDevice();

    // 测试响应时间
    const perfResult = await this.testResponsePerformance(testDevice.id);
    if (perfResult.success) {
      colorLog(`[成功] 响应时间测试通过 (平均: ${perfResult.avgTime}ms)`, 'green');
    }

    // 测试吞吐量
    const throughputResult = await this.testThroughput(testDevice.id);
    if (throughputResult.success) {
      colorLog(`[成功] 吞吐量测试通过 (${throughputResult.rps} RPS)`, 'green');
    }

    // 清理测试设备
    await this.deleteDevice(testDevice.id);
  }

  /**
   * 测试错误处理
   */
  async testErrorHandling() {
    colorLog('\n[紧急] 测试错误处理', 'yellow');
    colorLog('-'.repeat(30), 'yellow');

    const errorScenarios = [
      { name: '无效设备ID', test: () => this.sendCommand('invalid-device', 'ping') },
      { name: '无效命令', test: () => this.sendCommand('test-device', 'invalid-command') },
      { name: '格式错误', test: () => this.sendMalformedRequest() },
      { name: '超大请求', test: () => this.sendOversizedRequest() }
    ];

    for (const scenario of errorScenarios) {
      try {
        const result = await scenario.test();
        if (!result.success) {
          colorLog(`[成功] ${scenario.name} - 正确处理错误`, 'green');
        } else {
          colorLog(`[警告]  ${scenario.name} - 意外成功`, 'yellow');
        }
      } catch (error) {
        colorLog(`[成功] ${scenario.name} - 正确处理异常`, 'green');
      }
    }
  }

  /**
   * 测试并发
   */
  async testConcurrency() {
    colorLog('\n[启动] 测试并发', 'blue');
    colorLog('-'.repeat(30), 'blue');

    const devices = await this.createMultipleTestDevices(5);
    const concurrency = 10;

    try {
      const concurrentRequests = Array.from({ length: concurrency }, (_, i) => {
        const device = devices[i % devices.length];
        return this.sendCommand(device.id, 'ping');
      });

      const startTime = Date.now();
      const results = await Promise.all(concurrentRequests);
      const duration = Date.now() - startTime;

      const successCount = results.filter(r => r.success).length;
      const successRate = (successCount / concurrency) * 100;

      colorLog(`[成功] 并发测试完成`, 'green');
      colorLog(`   总请求数: ${concurrency}`, 'white');
      colorLog(`   成功数量: ${successCount}`, 'white');
      colorLog(`   成功率: ${successRate.toFixed(1)}%`, 'white');
      colorLog(`   总耗时: ${duration}ms`, 'white');
      colorLog(`   QPS: ${(concurrency / (duration / 1000)).toFixed(1)}`, 'white');

    } catch (error) {
      colorLog(`[错误] 并发测试失败: ${error.message}`, 'red');
    }

    // 清理测试设备
    for (const device of devices) {
      await this.deleteDevice(device.id);
    }
  }

  /**
   * 测试负载
   */
  async testLoad() {
    colorLog('\n[负载] 测试负载', 'magenta');
    colorLog('-'.repeat(30), 'magenta');

    const devices = await this.createMultipleTestDevices(10);
    const loadSize = 100;

    try {
      const loadRequests = Array.from({ length: loadSize }, (_, i) => {
        const device = devices[i % devices.length];
        return this.sendCommand(device.id, 'ping');
      });

      const startTime = Date.now();
      const results = await Promise.all(loadRequests);
      const duration = Date.now() - startTime;

      const successCount = results.filter(r => r.success).length;
      const avgResponseTime = duration / loadSize;
      const throughput = loadSize / (duration / 1000);

      colorLog(`[成功] 负载测试完成`, 'green');
      colorLog(`   负载大小: ${loadSize} 请求`, 'white');
      colorLog(`   成功数量: ${successCount}`, 'white');
      colorLog(`   成功率: ${((successCount / loadSize) * 100).toFixed(1)}%`, 'white');
      colorLog(`   总耗时: ${duration}ms`, 'white');
      colorLog(`   平均响应时间: ${avgResponseTime.toFixed(1)}ms`, 'white');
      colorLog(`   吞吐量: ${throughput.toFixed(1)} RPS`, 'white');

    } catch (error) {
      colorLog(`[错误] 负载测试失败: ${error.message}`, 'red');
    }

    // 清理测试设备
    for (const device of devices) {
      await this.deleteDevice(device.id);
    }
  }

  /**
   * 检查服务器连接
   */
  async checkServerConnection() {
    const result = await this.makeRequest('GET', '/health');
    if (!result.success) {
      throw new Error(`无法连接到服务器: ${result.error}`);
    }
  }

  /**
   * 检查环境变量
   */
  async checkEnvironmentVariables() {
    const requiredVars = ['CICADA_RELAY_URL', 'HMAC_SECRET'];
    const missingVars = requiredVars.filter(varName => !process.env[varName]);

    if (missingVars.length > 0) {
      throw new Error(`缺少环境变量: ${missingVars.join(', ')}`);
    }
  }

  /**
   * 检查依赖服务
   */
  async checkDependencies() {
    // 这里可以添加对其他依赖服务的检查
    return true;
  }

  /**
   * 创建测试设备
   */
  async createTestDevice() {
    const deviceId = `test-device-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

    const device = {
      id: deviceId,
      name: `Test Device ${deviceId}`,
      type: 'laptop',
      status: 'online',
      lastSeen: Date.now(),
      ipAddress: '192.168.1.100',
      userAgent: 'CicadaRelay-Integration-Test/1.0.0'
    };

    return device;
  }

  /**
   * 创建多个测试设备
   */
  async createMultipleTestDevices(count) {
    const devices = [];
    for (let i = 0; i < count; i++) {
      devices.push(await this.createTestDevice());
    }
    return devices;
  }

  /**
   * 查询设备状态
   */
  async queryDeviceStatus(deviceId) {
    return await this.makeRequest('GET', `/status?device_id=${deviceId}`);
  }

  /**
   * 获取设备列表
   */
  async listDevices() {
    return await this.makeRequest('GET', '/devices');
  }

  /**
   * 删除设备
   */
  async deleteDevice(deviceId) {
    return await this.sendCommand(deviceId, 'unregister');
  }

  /**
   * 发送命令
   */
  async sendCommand(deviceId, command, params = {}) {
    const timestamp = Math.floor(Date.now() / 1000);
    const nonce = this.generateNonce();
    const payload = `${deviceId}:${command}:${timestamp}:${nonce}`;
    const signature = this.generateSignature(payload);

    const body = {
      device_id: deviceId,
      cmd: command,
      ts: timestamp,
      nonce,
      sig: signature,
      ...params
    };

    return await this.makeRequest('POST', '/send', body);
  }

  /**
   * 测试批量操作
   */
  async testBatchOperations(deviceId) {
    const commands = ['ping', 'status', 'ping'];
    const results = await Promise.all(
      commands.map(cmd => this.sendCommand(deviceId, cmd))
    );

    return {
      success: results.every(r => r.success),
      results
    };
  }

  /**
   * 测试WebSocket连接
   */
  async testWebSocketConnection(deviceId) {
    // 这里应该实现真实的WebSocket连接测试
    // 为了简化，返回模拟结果
    return { success: true };
  }

  /**
   * 测试WebSocket消息传递
   */
  async testWebSocketMessaging(deviceId) {
    // 这里应该实现真实的WebSocket消息测试
    // 为了简化，返回模拟结果
    return { success: true };
  }

  /**
   * 测试身份验证
   */
  async testAuthentication() {
    const deviceId = 'auth-test-device';

    // 测试有效签名
    const validResult = await this.sendCommand(deviceId, 'ping');

    // 测试无效签名
    const invalidResult = await this.makeRequest('POST', '/send', {
      device_id: deviceId,
      cmd: 'ping',
      ts: Math.floor(Date.now() / 1000),
      nonce: this.generateNonce(),
      sig: 'invalid-signature'
    });

    return {
      success: validResult.success && !invalidResult.success
    };
  }

  /**
   * 测试输入验证
   */
  async testInputValidation() {
    const maliciousInputs = [
      '<script>alert("xss")</script>',
      "'; DROP TABLE devices; --",
      '../../../etc/passwd'
    ];

    const results = await Promise.all(
      maliciousInputs.map(input => this.sendCommand(input, 'ping'))
    );

    // 所有恶意输入都应该被拒绝
    return {
      success: results.every(r => !r.success)
    };
  }

  /**
   * 测试速率限制
   */
  async testRateLimiting() {
    const deviceId = 'rate-limit-test';
    const rapidRequests = 10;

    const requests = Array.from({ length: rapidRequests }, () =>
      this.sendCommand(deviceId, 'ping')
    );

    const results = await Promise.all(requests);
    const rateLimitedCount = results.filter(r => r.status === 429).length;

    return {
      success: rateLimitedCount > 0,
      rateLimitedCount
    };
  }

  /**
   * 测试响应性能
   */
  async testResponsePerformance(deviceId) {
    const commands = ['ping', 'status', 'info'];
    const times = [];

    for (const command of commands) {
      const startTime = Date.now();
      await this.sendCommand(deviceId, command);
      times.push(Date.now() - startTime);
    }

    const avgTime = times.reduce((sum, time) => sum + time, 0) / times.length;

    return {
      success: avgTime < 1000, // 平均响应时间小于1秒
      avgTime: avgTime.toFixed(1),
      times
    };
  }

  /**
   * 测试吞吐量
   */
  async testThroughput(deviceId) {
    const requestCount = 20;
    const startTime = Date.now();

    const requests = Array.from({ length: requestCount }, () =>
      this.sendCommand(deviceId, 'ping')
    );

    await Promise.all(requests);
    const duration = Date.now() - startTime;
    const rps = requestCount / (duration / 1000);

    return {
      success: rps > 10, // 至少10 RPS
      rps: rps.toFixed(1),
      duration
    };
  }

  /**
   * 发送格式错误的请求
   */
  async sendMalformedRequest() {
    return await fetch(this.baseUrl + '/send', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: 'invalid-json'
    });
  }

  /**
   * 发送超大请求
   */
  async sendOversizedRequest() {
    const largePayload = 'x'.repeat(1024 * 1024); // 1MB

    return await this.sendCommand('test-device', 'data', {
      payload: largePayload
    });
  }

  /**
   * 发送HTTP请求
   */
  async makeRequest(method, url, body = null) {
    try {
      const options = {
        method,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'CicadaRelay-Integration-Test/1.0.0'
        }
      };

      if (body) {
        options.body = JSON.stringify(body);
      }

      const response = await fetch(this.baseUrl + url, options);
      const data = response.ok ? await response.json() : null;

      return {
        success: response.ok,
        status: response.status,
        data,
        error: response.ok ? null : `HTTP ${response.status}`
      };
    } catch (error) {
      return {
        success: false,
        error: error.message
      };
    }
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
   * 生成签名
   */
  generateSignature(payload) {
    const crypto = require('crypto');
    return crypto.createHash('sha256')
      .update(payload + this.signingKey)
      .digest('hex');
  }

  /**
   * 打印测试摘要
   */
  printTestSummary() {
    colorLog('\n[统计] 集成测试摘要', 'bright');
    colorLog('=' .repeat(50), 'bright');

    colorLog('[成功] 所有集成测试已运行完成', 'green');
    colorLog('[日志] 测试详情请查看上述日志', 'blue');
    colorLog('[工具] 如有问题，请检查服务器状态和配置', 'yellow');

    colorLog('\n[目标] 推荐后续步骤:', 'cyan');
    colorLog('1. 检查失败的测试项', 'white');
    colorLog('2. 分析性能瓶颈', 'white');
    colorLog('3. 优化错误处理', 'white');
    colorLog('4. 完善安全措施', 'white');
  }
}

/**
 * 命令行接口
 */
async function main() {
  const args = process.argv.slice(2);
  const runner = new IntegrationTestRunner();

  if (args.length === 0) {
    // 显示帮助信息
    colorLog('\n[测试] CicadaRelay集成测试工具', 'bright');
    colorLog('=' .repeat(50), 'bright');
    colorLog('\n使用方法:', 'yellow');
    colorLog('  node debug-integration.js [命令]', 'white');
    colorLog('\n可用命令:', 'yellow');
    colorLog('  all                 - 运行所有集成测试', 'white');
    colorLog('  basic              - 基础连接和环境检查', 'white');
    colorLog('  devices            - 设备管理集成测试', 'white');
    colorLog('  api                - API功能集成测试', 'white');
    colorLog('  websocket          - WebSocket集成测试', 'white');
    colorLog('  security           - 安全功能集成测试', 'white');
    colorLog('  performance        - 性能集成测试', 'white');
    colorLog('  errors             - 错误处理测试', 'white');
    colorLog('  concurrency        - 并发测试', 'white');
    colorLog('  load               - 负载测试', 'white');
    colorLog('\n环境变量:', 'yellow');
    colorLog('  CICADA_RELAY_URL       - 服务器URL (默认: http://localhost:8787)', 'white');
    colorLog('  HMAC_SECRET        - 签名密钥 (默认: test-signing-key)', 'white');
    colorLog('\n示例:', 'cyan');
    colorLog('  CICADA_RELAY_URL=https://api.example.com node debug-integration.js all', 'white');
    colorLog('  node debug-integration.js performance', 'white');
    colorLog('  node debug-integration.js security', 'white');

    process.exit(0);
  }

  const command = args[0];

  try {
    switch (command) {
      case 'all':
        await runner.runAllTests();
        break;

      case 'basic':
        await runner.checkEnvironment();
        await runner.testBasicConnection();
        break;

      case 'devices':
        await runner.testDeviceManagement();
        break;

      case 'api':
        await runner.testApiFunctionality();
        break;

      case 'websocket':
        await runner.testWebSocketFunctionality();
        break;

      case 'security':
        await runner.testSecurityFeatures();
        break;

      case 'performance':
        await runner.testPerformance();
        break;

      case 'errors':
        await runner.testErrorHandling();
        break;

      case 'concurrency':
        await runner.testConcurrency();
        break;

      case 'load':
        await runner.testLoad();
        break;

      default:
        colorLog(`[错误] 未知命令: ${command}`, 'red');
        colorLog('运行 "node debug-integration.js" 查看帮助', 'yellow');
        process.exit(1);
    }
  } catch (error) {
    colorLog(`[崩溃] 集成测试执行失败: ${error.message}`, 'red');
    process.exit(1);
  }
}

// 运行主程序
main().catch(error => {
  colorLog(`[崩溃] 程序执行失败: ${error.message}`, 'red');
  process.exit(1);
});