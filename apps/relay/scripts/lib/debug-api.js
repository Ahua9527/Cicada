#!/usr/bin/env node

/**
 * CicadaRelay API调试工具
 *
 * 提供API测试、签名生成、请求模拟等功能
 */

import { createHash } from 'crypto';
import { WebSocket } from 'ws';

// 配置
const CONFIG = {
  BASE_URL: process.env.CICADA_RELAY_URL || 'http://localhost:8787',
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
  colorLog(`\n[查询] ${title}:`, color);
  console.log(JSON.stringify(obj, null, 2));
}

/**
 * 创建API Key认证的请求
 */
function createApiKeyRequest(deviceId, command, params = {}) {
  const timestamp = Math.floor(Date.now() / 1000);

  return {
    device_id: deviceId,
    cmd: command,
    ts: timestamp,
    api_key: CONFIG.API_KEY,
    params
  };
}

/**
 * 生成时间戳
 */
function getTimestamp() {
  return Math.floor(Date.now() / 1000);
}

/**
 * 生成随机nonce
 */
function generateNonce(length = 32) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

/**
 * 创建API Key认证的命令请求
 */
function createSignedCommand(deviceId, command, params = {}) {
  return createApiKeyRequest(deviceId, command, params);
}

/**
 * 创建WebSocket连接参数
 */
function createWebSocketSignature(deviceId) {
  const timestamp = getTimestamp();

  return {
    device_id: deviceId,
    api_key: CONFIG.API_KEY,
    ts: timestamp
  };
}

/**
 * 发送HTTP请求
 */
async function sendRequest(url, options = {}) {
  try {
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'CicadaRelay-Debug-Tool/1.0.0'
      },
      ...options
    });

    const data = await response.json();
    return { success: true, status: response.status, data };
  } catch (error) {
    return { success: false, error: error.message };
  }
}

/**
 * API调试测试套件
 */
class APIDebugger {
  constructor() {
    this.baseUrl = CONFIG.BASE_URL;
    this.deviceId = CONFIG.DEFAULT_DEVICE_ID;
  }

  /**
   * 健康检查
   */
  async healthCheck() {
    colorLog('\n🏥 健康检查', 'cyan');
    colorLog('=' .repeat(50), 'cyan');

    const result = await sendRequest(`${this.baseUrl}/health`);

    if (result.success) {
      colorLog('[成功] 健康检查成功', 'green');
      colorLogJson(result.data, '响应数据', 'blue');
    } else {
      colorLog('[错误] 健康检查失败', 'red');
      colorLog(`错误: ${result.error}`, 'red');
    }
  }

  /**
   * 设备状态查询
   */
  async checkDeviceStatus(deviceId = this.deviceId) {
    colorLog('\n[设备] 设备状态查询', 'magenta');
    colorLog('=' .repeat(50), 'magenta');
    colorLog(`设备ID: ${deviceId}`, 'blue');

    const result = await sendRequest(`${this.baseUrl}/status?device_id=${deviceId}`);

    if (result.success) {
      colorLog('[成功] 状态查询成功', 'green');
      colorLogJson(result.data, '设备状态', 'blue');
    } else {
      colorLog('[错误] 状态查询失败', 'red');
      colorLog(`错误: ${result.error}`, 'red');
    }
  }

  /**
   * 设备列表查询
   */
  async listDevices() {
    colorLog('\n[列表] 设备列表查询', 'yellow');
    colorLog('=' .repeat(50), 'yellow');

    const result = await sendRequest(`${this.baseUrl}/devices`);

    if (result.success) {
      colorLog('[成功] 设备列表获取成功', 'green');
      colorLogJson(result.data, '设备列表', 'blue');
    } else {
      colorLog('[错误] 设备列表获取失败', 'red');
      colorLog(`错误: ${result.error}`, 'red');
    }
  }

  /**
   * 发送命令
   */
  async sendCommand(command, deviceId = this.deviceId, params = {}) {
    colorLog('\n📤 发送命令', 'blue');
    colorLog('=' .repeat(50), 'blue');
    colorLog(`设备ID: ${deviceId}`, 'blue');
    colorLog(`命令: ${command}`, 'blue');

    const request = createSignedCommand(deviceId, command, params);
    colorLog('\n[列表] 请求数据:', 'yellow');
    colorLogJson(request, '签名请求', 'yellow');

    const result = await sendRequest(`${this.baseUrl}/send`, {
      method: 'POST',
      body: JSON.stringify(request)
    });

    if (result.success) {
      colorLog('[成功] 命令发送成功', 'green');
      colorLogJson(result.data, '响应数据', 'blue');
    } else {
      colorLog('[错误] 命令发送失败', 'red');
      colorLog(`错误: ${result.error}`, 'red');
    }
  }

  /**
   * WebSocket连接测试
   */
  async testWebSocket(deviceId = this.deviceId) {
    colorLog('\n[连接] WebSocket连接测试', 'cyan');
    colorLog('=' .repeat(50), 'cyan');
    colorLog(`设备ID: ${deviceId}`, 'blue');

    const wsParams = createWebSocketSignature(deviceId);
    colorLog('\n[列表] 连接参数:', 'yellow');
    colorLogJson(wsParams, 'WebSocket参数', 'yellow');

    const wsUrl = `${this.baseUrl.replace('http', 'ws')}/ws?${new URLSearchParams(wsParams).toString()}`;
    colorLog(`\n[链接] WebSocket URL: ${wsUrl}`, 'blue');

    return new Promise((resolve, reject) => {
      const ws = new WebSocket(wsUrl);
      let messageCount = 0;

      const timeout = setTimeout(() => {
        ws.close();
        colorLog('[时间] WebSocket连接超时', 'yellow');
        resolve({ success: false, error: 'Connection timeout' });
      }, 10000);

      ws.on('open', () => {
        colorLog('[成功] WebSocket连接成功', 'green');

        // 发送测试消息
        const testMessage = {
          type: 'ping',
          timestamp: Date.now()
        };
        ws.send(JSON.stringify(testMessage));
        colorLog('📤 发送ping消息', 'blue');
      });

      ws.on('message', (data) => {
        try {
          const message = JSON.parse(data);
          messageCount++;
          colorLog(`📨 收到消息 #${messageCount}:`, 'green');
          colorLogJson(message, '消息内容', 'blue');

          if (messageCount >= 2) {
            clearTimeout(timeout);
            ws.close();
            resolve({ success: true, messageCount });
          }
        } catch (error) {
          colorLog(`[错误] 消息解析失败: ${error.message}`, 'red');
        }
      });

      ws.on('error', (error) => {
        clearTimeout(timeout);
        colorLog('[错误] WebSocket错误', 'red');
        colorLog(error.message, 'red');
        resolve({ success: false, error: error.message });
      });

      ws.on('close', () => {
        clearTimeout(timeout);
        colorLog('[连接] WebSocket连接已关闭', 'yellow');
      });
    });
  }

  /**
   * 运行完整测试套件
   */
  async runFullTestSuite() {
    colorLog('\n[启动] CicadaRelay API调试测试开始', 'bright');
    colorLog('=' .repeat(60), 'bright');
    colorLog(`基础URL: ${this.baseUrl}`, 'cyan');
    colorLog(`设备ID: ${this.deviceId}`, 'cyan');

    // 健康检查
    await this.healthCheck();
    await new Promise(resolve => setTimeout(resolve, 1000));

    // 设备状态查询
    await this.checkDeviceStatus();
    await new Promise(resolve => setTimeout(resolve, 1000));

    // 设备列表查询
    await this.listDevices();
    await new Promise(resolve => setTimeout(resolve, 1000));

    // 发送ping命令
    await this.sendCommand('ping');
    await new Promise(resolve => setTimeout(resolve, 1000));

    // 发送状态查询命令
    await this.sendCommand('status');
    await new Promise(resolve => setTimeout(resolve, 1000));

    // WebSocket连接测试
    await this.testWebSocket();

    colorLog('\n[完成] API调试测试完成', 'bright');
    colorLog('=' .repeat(60), 'bright');
  }
}

/**
 * 命令行接口
 */
async function main() {
  const args = process.argv.slice(2);
  const apiDebugger = new APIDebugger();

  if (args.length === 0) {
    // 显示帮助信息
    colorLog('\n[工具] CicadaRelay API调试工具', 'bright');
    colorLog('=' .repeat(50), 'bright');
    colorLog('\n使用方法:', 'yellow');
    colorLog('  node debug-api.js [命令] [参数]', 'white');
    colorLog('\n可用命令:', 'yellow');
    colorLog('  health              - 健康检查', 'white');
    colorLog('  status [device_id]  - 设备状态查询', 'white');
    colorLog('  list                - 设备列表查询', 'white');
    colorLog('  send <command>      - 发送命令', 'white');
    colorLog('  ws [device_id]      - WebSocket连接测试', 'white');
    colorLog('  full                - 运行完整测试套件', 'white');
    colorLog('\n支持命令:', 'white');
    colorLog('  ping, status, lock, bt_on, bt_off, sleep_hold, sleep_release', 'cyan');
    colorLog('\n示例:', 'yellow');
    colorLog('  node debug-api.js health', 'white');
    colorLog('  node debug-api.js send ping', 'white');
    colorLog('  node debug-api.js send lock device-123', 'white');
    colorLog('  node debug-api.js ws debug-device-001', 'white');
    colorLog('  node debug-api.js full', 'white');

    process.exit(0);
  }

  const command = args[0];

  switch (command) {
    case 'health':
      await apiDebugger.healthCheck();
      break;

    case 'status':
      const deviceId = args[1] || CONFIG.DEFAULT_DEVICE_ID;
      await apiDebugger.checkDeviceStatus(deviceId);
      break;

    case 'list':
      await apiDebugger.listDevices();
      break;

    case 'send':
      const cmd = args[1];
      if (!cmd) {
        colorLog('[错误] 请指定要发送的命令', 'red');
        colorLog('支持的命令: ping, status, lock, bt_on, bt_off, sleep_hold, sleep_release', 'yellow');
        process.exit(1);
      }
      const sendDeviceId = args[2] || CONFIG.DEFAULT_DEVICE_ID;
      await apiDebugger.sendCommand(cmd, sendDeviceId);
      break;

    case 'ws':
      const wsDeviceId = args[1] || CONFIG.DEFAULT_DEVICE_ID;
      await apiDebugger.testWebSocket(wsDeviceId);
      break;

    case 'full':
      await apiDebugger.runFullTestSuite();
      break;

    default:
      colorLog(`[错误] 未知命令: ${command}`, 'red');
      colorLog('运行 "node debug-api.js" 查看帮助', 'yellow');
      process.exit(1);
  }
}

// 运行主程序
main().catch(error => {
  colorLog(`[崩溃] 程序执行失败: ${error.message}`, 'red');
  process.exit(1);
});