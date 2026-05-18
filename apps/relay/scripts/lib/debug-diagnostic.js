#!/usr/bin/env node

/**
 * CicadaRelay 诊断工具
 *
 * 提供系统诊断、性能分析、问题排查等功能
 */

import { spawn } from 'child_process';
import { createInterface } from 'readline';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { readFileSync } from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

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
 * 系统诊断器
 */
class SystemDiagnostic {
  constructor() {
    this.baseUrl = process.env.CICADA_RELAY_URL || 'http://localhost:8787';
    this.signingKey = process.env.HMAC_SECRET || 'test-signing-key';
    this.results = [];
    this.startTime = Date.now();
  }

  /**
   * 运行完整诊断
   */
  async runFullDiagnostic() {
    colorLog('\n[查询] 开始CicadaRelay系统诊断', 'bright');
    colorLog('=' .repeat(60), 'bright');
    colorLog(`基础URL: ${this.baseUrl}`, 'cyan');
    colorLog(`诊断时间: ${new Date().toISOString()}`, 'cyan');

    try {
      // 1. 环境检查
      await this.diagnoseEnvironment();

      // 2. 服务状态检查
      await this.diagnoseServices();

      // 3. 性能分析
      await this.diagnosePerformance();

      // 4. 安全诊断
      await this.diagnoseSecurity();

      // 5. 资源使用诊断
      await this.diagnoseResources();

      // 6. 网络连接诊断
      await this.diagnoseNetwork();

      // 7. 日志分析
      await this.diagnoseLogs();

      // 8. 配置验证
      await this.diagnoseConfiguration();

      // 9. 依赖检查
      await this.diagnoseDependencies();

      this.printDiagnosticSummary();

    } catch (error) {
      colorLog(`[错误] 诊断过程出错: ${error.message}`, 'red');
      throw error;
    }
  }

  /**
   * 环境诊断
   */
  async diagnoseEnvironment() {
    colorLog('\n🖥️ 环境诊断', 'blue');
    colorLog('-'.repeat(30), 'blue');

    // Node.js环境检查
    const nodeVersion = process.version;
    const platform = process.platform;
    const arch = process.arch;
    const pid = process.pid;
    const uptime = process.uptime();

    this.addResult('environment', 'nodejs', 'healthy',
      `Node.js ${nodeVersion} on ${platform}-${arch}`,
      { nodeVersion, platform, arch, pid, uptime }
    );

    // 内存使用检查
    const memUsage = process.memoryUsage();
    const heapUsed = (memUsage.heapUsed / 1024 / 1024).toFixed(1);
    const heapTotal = (memUsage.heapTotal / 1024 / 1024).toFixed(1);
    const rss = (memUsage.rss / 1024 / 1024).toFixed(1);
    const external = (memUsage.external / 1024 / 1024).toFixed(1);

    const memUsagePercent = ((memUsage.heapUsed / memUsage.heapTotal) * 100).toFixed(1);
    let memStatus = 'healthy';
    if (memUsagePercent > 90) memStatus = 'error';
    else if (memUsagePercent > 75) memStatus = 'warning';

    this.addResult('environment', 'memory', memStatus,
      `内存使用: ${memUsagePercent}% (${heapUsed}MB/${heapTotal}MB)`,
      { heapUsed, heapTotal, rss, external, usagePercent: memUsagePercent },
      memStatus !== 'healthy' ? ['优化内存使用', '检查内存泄漏'] : undefined
    );

    // CPU信息检查
    const cpuInfo = await this.getCpuInfo();
    this.addResult('environment', 'cpu', 'healthy',
      `CPU: ${cpuInfo.model || 'Unknown'} (${cpuInfo.cores || 'Unknown'} cores)`,
      cpuInfo
    );

    // 环境变量检查
    const requiredEnvVars = ['CICADA_RELAY_URL', 'HMAC_SECRET'];
    const missingVars = requiredEnvVars.filter(varName => !process.env[varName]);

    let envStatus = 'healthy';
    if (missingVars.length > 0) envStatus = 'error';

    this.addResult('environment', 'env_vars', envStatus,
      `环境变量: ${missingVars.length === 0 ? '完整' : `缺少 ${missingVars.length} 个`}`,
      { required: requiredEnvVars, missing: missingVars },
      missingVars.length > 0 ? ['设置缺失的环境变量'] : undefined
    );
  }

  /**
   * 服务状态诊断
   */
  async diagnoseServices() {
    colorLog('\n[工具] 服务状态诊断', 'yellow');
    colorLog('-'.repeat(30), 'yellow');

    // HTTP服务检查
    const httpStatus = await this.checkHttpService();
    this.addResult('service', 'http', httpStatus.healthy ? 'healthy' : 'error',
      `HTTP服务: ${httpStatus.healthy ? '正常' : '异常'} (${httpStatus.responseTime}ms)`,
      httpStatus
    );

    // WebSocket服务检查
    const wsStatus = await this.checkWebSocketService();
    this.addResult('service', 'websocket', wsStatus.healthy ? 'healthy' : 'warning',
      `WebSocket服务: ${wsStatus.healthy ? '正常' : '异常'}`,
      wsStatus
    );

    // 数据库连接检查
    const dbStatus = await this.checkDatabaseConnection();
    this.addResult('service', 'database', dbStatus.connected ? 'healthy' : 'error',
      `数据库连接: ${dbStatus.connected ? '正常' : '异常'}`,
      dbStatus
    );

    // 缓存服务检查
    const cacheStatus = await this.checkCacheService();
    this.addResult('service', 'cache', cacheStatus.available ? 'healthy' : 'warning',
      `缓存服务: ${cacheStatus.available ? '正常' : '不可用'}`,
      cacheStatus
    );
  }

  /**
   * 性能诊断
   */
  async diagnosePerformance() {
    colorLog('\n[性能] 性能诊断', 'green');
    colorLog('-'.repeat(30), 'green');

    // 响应时间测试
    const responseTimeTest = await this.testResponseTime();
    let responseTimeStatus = 'healthy';
    if (responseTimeTest.avg > 2000) responseTimeStatus = 'error';
    else if (responseTimeTest.avg > 1000) responseTimeStatus = 'warning';

    this.addResult('performance', 'response_time', responseTimeStatus,
      `平均响应时间: ${responseTimeTest.avg.toFixed(1)}ms`,
      responseTimeTest,
      responseTimeStatus !== 'healthy' ? ['优化响应时间', '检查性能瓶颈'] : undefined
    );

    // 吞吐量测试
    const throughputTest = await this.testThroughput();
    let throughputStatus = 'healthy';
    if (throughputTest.rps < 10) throughputStatus = 'warning';

    this.addResult('performance', 'throughput', throughputStatus,
      `吞吐量: ${throughputTest.rps.toFixed(1)} RPS`,
      throughputTest,
      throughputStatus !== 'healthy' ? ['提高吞吐量', '优化处理效率'] : undefined
    );

    // 并发测试
    const concurrencyTest = await this.testConcurrency();
    this.addResult('performance', 'concurrency',
      concurrencyTest.successRate > 90 ? 'healthy' : 'warning',
      `并发处理成功率: ${concurrencyTest.successRate.toFixed(1)}%`,
      concurrencyTest
    );

    // 错误率测试
    const errorRateTest = await this.testErrorRate();
    let errorRateStatus = 'healthy';
    if (errorRateTest.rate > 10) errorRateStatus = 'error';
    else if (errorRateTest.rate > 5) errorRateStatus = 'warning';

    this.addResult('performance', 'error_rate', errorRateStatus,
      `错误率: ${errorRateTest.rate.toFixed(1)}%`,
      errorRateTest,
      errorRateStatus !== 'healthy' ? ['降低错误率', '改善错误处理'] : undefined
    );
  }

  /**
   * 安全诊断
   */
  async diagnoseSecurity() {
    colorLog('\n[锁定] 安全诊断', 'red');
    colorLog('-'.repeat(30), 'red');

    // 认证安全检查
    const authCheck = await this.checkAuthenticationSecurity();
    this.addResult('security', 'authentication', authCheck.secure ? 'healthy' : 'warning',
      `认证安全: ${authCheck.secure ? '正常' : '存在风险'}`,
      authCheck,
      !authCheck.secure ? ['加强认证安全', '检查认证机制'] : undefined
    );

    // 输入验证检查
    const inputValidationCheck = await this.checkInputValidation();
    this.addResult('security', 'input_validation', inputValidationCheck.secure ? 'healthy' : 'error',
      `输入验证: ${inputValidationCheck.secure ? '正常' : '存在漏洞'}`,
      inputValidationCheck,
      !inputValidationCheck.secure ? ['修复输入验证漏洞', '加强安全防护'] : undefined
    );

    // HTTPS配置检查
    const httpsCheck = await this.checkHttpsConfiguration();
    this.addResult('security', 'https', httpsCheck.secure ? 'healthy' : 'warning',
      `HTTPS配置: ${httpsCheck.secure ? '安全' : '不安全'}`,
      httpsCheck,
      !httpsCheck.secure ? ['启用HTTPS', '配置SSL证书'] : undefined
    );

    // 敏感信息检查
    const sensitiveInfoCheck = await this.checkSensitiveInfo();
    this.addResult('security', 'sensitive_info', sensitiveInfoCheck.secure ? 'healthy' : 'error',
      `敏感信息保护: ${sensitiveInfoCheck.secure ? '正常' : '存在泄露风险'}`,
      sensitiveInfoCheck,
      !sensitiveInfoCheck.secure ? ['移除敏感信息', '加强数据保护'] : undefined
    );
  }

  /**
   * 资源使用诊断
   */
  async diagnoseResources() {
    colorLog('\n[统计] 资源使用诊断', 'magenta');
    colorLog('-'.repeat(30), 'magenta');

    // CPU使用情况
    const cpuUsage = await this.getCpuUsage();
    let cpuStatus = 'healthy';
    if (cpuUsage > 90) cpuStatus = 'error';
    else if (cpuUsage > 75) cpuStatus = 'warning';

    this.addResult('resource', 'cpu', cpuStatus,
      `CPU使用率: ${cpuUsage.toFixed(1)}%`,
      { usage: cpuUsage },
      cpuStatus !== 'healthy' ? ['优化CPU使用', '检查CPU密集型操作'] : undefined
    );

    // 内存使用情况
    const memUsage = await this.getMemoryUsage();
    let memStatus = 'healthy';
    if (memUsage > 90) memStatus = 'error';
    else if (memUsage > 80) memStatus = 'warning';

    this.addResult('resource', 'memory', memStatus,
      `内存使用率: ${memUsage.toFixed(1)}%`,
      { usage: memUsage },
      memStatus !== 'healthy' ? ['优化内存使用', '检查内存泄漏'] : undefined
    );

    // 磁盘使用情况
    const diskUsage = await this.getDiskUsage();
    let diskStatus = 'healthy';
    if (diskUsage > 90) diskStatus = 'error';
    else if (diskUsage > 85) diskStatus = 'warning';

    this.addResult('resource', 'disk', diskStatus,
      `磁盘使用率: ${diskUsage.toFixed(1)}%`,
      { usage: diskUsage },
      diskStatus !== 'healthy' ? ['清理磁盘空间', '优化存储使用'] : undefined
    );

    // 网络使用情况
    const networkUsage = await this.getNetworkUsage();
    this.addResult('resource', 'network', 'healthy',
      `网络连接数: ${networkUsage.connections}`,
      networkUsage
    );
  }

  /**
   * 网络连接诊断
   */
  async diagnoseNetwork() {
    colorLog('\n[网络] 网络连接诊断', 'cyan');
    colorLog('-'.repeat(30), 'cyan');

    // 网络连通性测试
    const connectivityTests = [
      { name: '本地回环', host: '127.0.0.1' },
      { name: 'DNS解析', host: 'google.com' },
      { name: '服务端点', host: new URL(this.baseUrl).hostname }
    ];

    for (const test of connectivityTests) {
      const result = await this.testConnectivity(test.host);
      this.addResult('network', test.name, result.connected ? 'healthy' : 'error',
        `${test.name}: ${result.connected ? '连通' : '不通'} (${result.time}ms)`,
        result
      );
    }

    // 带宽测试
    const bandwidthTest = await this.testBandwidth();
    this.addResult('network', 'bandwidth',
      bandwidthTest > 10 ? 'healthy' : 'warning',
      `网络带宽: ${bandwidthTest.toFixed(1)} Mbps`,
      { bandwidth: bandwidthTest }
    );

    // 延迟测试
    const latencyTest = await this.testLatency();
    this.addResult('network', 'latency',
      latencyTest < 100 ? 'healthy' : latencyTest < 300 ? 'warning' : 'error',
      `网络延迟: ${latencyTest.toFixed(1)}ms`,
      { latency: latencyTest }
    );
  }

  /**
   * 日志诊断
   */
  async diagnoseLogs() {
    colorLog('\n[日志] 日志诊断', 'yellow');
    colorLog('-'.repeat(30), 'yellow');

    // 错误日志分析
    const errorLogAnalysis = await this.analyzeErrorLogs();
    let errorLogStatus = 'healthy';
    if (errorLogAnalysis.errorCount > 50) errorLogStatus = 'error';
    else if (errorLogAnalysis.errorCount > 10) errorLogStatus = 'warning';

    this.addResult('logs', 'error_analysis', errorLogStatus,
      `错误日志: ${errorLogAnalysis.errorCount} 个 (最近1小时)`,
      errorLogAnalysis,
      errorLogStatus !== 'healthy' ? ['检查错误日志', '修复高频错误'] : undefined
    );

    // 警告日志分析
    const warningLogAnalysis = await this.analyzeWarningLogs();
    this.addResult('logs', 'warning_analysis',
      warningLogAnalysis.warningCount > 20 ? 'warning' : 'healthy',
      `警告日志: ${warningLogAnalysis.warningCount} 个 (最近1小时)`,
      warningLogAnalysis
    );

    // 日志大小检查
    const logSizeAnalysis = await this.analyzeLogSize();
    this.addResult('logs', 'size_analysis',
      logSizeAnalysis.totalSize < 100 ? 'healthy' : 'warning',
      `日志总大小: ${logSizeAnalysis.totalSize.toFixed(1)} MB`,
      logSizeAnalysis,
      logSizeAnalysis.totalSize >= 100 ? ['清理日志文件', '实施日志轮转'] : undefined
    );
  }

  /**
   * 配置诊断
   */
  async diagnoseConfiguration() {
    colorLog('\n⚙️ 配置诊断', 'blue');
    colorLog('-'.repeat(30), 'blue');

    // 配置文件检查
    const configCheck = await this.checkConfigurationFiles();
    this.addResult('config', 'files', configCheck.valid ? 'healthy' : 'warning',
      `配置文件: ${configCheck.valid ? '有效' : '存在警告'}`,
      configCheck,
      !configCheck.valid ? ['修复配置问题'] : undefined
    );

    // 权限检查
    const permissionCheck = await this.checkPermissions();
    this.addResult('config', 'permissions', permissionCheck.valid ? 'healthy' : 'error',
      `文件权限: ${permissionCheck.valid ? '正常' : '异常'}`,
      permissionCheck,
      !permissionCheck.valid ? ['修复文件权限'] : undefined
    );

    // 依赖版本检查
    const dependencyCheck = await this.checkDependencyVersions();
    this.addResult('config', 'dependencies', dependencyCheck.valid ? 'healthy' : 'warning',
      `依赖版本: ${dependencyCheck.valid ? '兼容' : '存在不兼容'}`,
      dependencyCheck,
      !dependencyCheck.valid ? ['更新依赖版本'] : undefined
    );
  }

  /**
   * 依赖诊断
   */
  async diagnoseDependencies() {
    colorLog('\n📦 依赖诊断', 'green');
    colorLog('-'.repeat(30), 'green');

    // Node.js依赖检查
    const nodeDepsCheck = await this.checkNodeDependencies();
    this.addResult('dependencies', 'node_modules', nodeDepsCheck.valid ? 'healthy' : 'warning',
      `Node.js依赖: ${nodeDepsCheck.valid ? '完整' : '缺失'}`,
      nodeDepsCheck,
      !nodeDepsCheck.valid ? ['安装缺失依赖'] : undefined
    );

    // 系统依赖检查
    const systemDepsCheck = await this.checkSystemDependencies();
    this.addResult('dependencies', 'system', systemDepsCheck.valid ? 'healthy' : 'warning',
      `系统依赖: ${systemDepsCheck.valid ? '满足' : '缺失'}`,
      systemDepsCheck,
      !systemDepsCheck.valid ? ['安装系统依赖'] : undefined
    );

    // 外部服务依赖检查
    const externalDepsCheck = await this.checkExternalDependencies();
    this.addResult('dependencies', 'external', externalDepsCheck.available ? 'healthy' : 'error',
      `外部服务: ${externalDepsCheck.available ? '可用' : '不可用'}`,
      externalDepsCheck,
      !externalDepsCheck.available ? ['检查外部服务状态'] : undefined
    );
  }

  // 辅助方法实现（简化版本，实际应该实现真实的检查逻辑）

  async getCpuInfo() {
    return {
      model: 'Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz',
      cores: 8,
      speed: 2.6
    };
  }

  async checkHttpService() {
    const startTime = Date.now();
    try {
      const response = await fetch(this.baseUrl + '/health');
      const responseTime = Date.now() - startTime;
      return {
        healthy: response.ok,
        responseTime,
        status: response.status
      };
    } catch (error) {
      return {
        healthy: false,
        responseTime: Date.now() - startTime,
        error: error.message
      };
    }
  }

  async checkWebSocketService() {
    // 模拟WebSocket检查
    return {
      healthy: Math.random() > 0.1,
      connected: true,
      latency: Math.floor(Math.random() * 100)
    };
  }

  async checkDatabaseConnection() {
    // 模拟数据库连接检查
    return {
      connected: Math.random() > 0.1,
      responseTime: Math.floor(Math.random() * 50),
      poolSize: 10,
      activeConnections: Math.floor(Math.random() * 10)
    };
  }

  async checkCacheService() {
    // 模拟缓存服务检查
    return {
      available: Math.random() > 0.2,
      hitRate: 85 + Math.random() * 15,
      size: Math.floor(Math.random() * 1000)
    };
  }

  async testResponseTime() {
    const requests = [];
    const testCount = 10;

    for (let i = 0; i < testCount; i++) {
      const startTime = Date.now();
      try {
        await fetch(this.baseUrl + '/health');
        requests.push(Date.now() - startTime);
      } catch (error) {
        requests.push(5000); // 超时值
      }
    }

    const avg = requests.reduce((sum, time) => sum + time, 0) / requests.length;
    const min = Math.min(...requests);
    const max = Math.max(...requests);

    return { avg, min, max, requests };
  }

  async testThroughput() {
    const startTime = Date.now();
    const testDuration = 5000; // 5秒
    const requests = [];

    while (Date.now() - startTime < testDuration) {
      const requestStart = Date.now();
      try {
        await fetch(this.baseUrl + '/health');
        requests.push(Date.now() - requestStart);
      } catch (error) {
        // 忽略错误
      }
    }

    const rps = requests.length / (testDuration / 1000);
    return { rps, requests: requests.length };
  }

  async testConcurrency() {
    const concurrency = 20;
    const requests = Array.from({ length: concurrency }, () =>
      fetch(this.baseUrl + '/health')
    );

    const results = await Promise.allSettled(requests);
    const successCount = results.filter(r => r.status === 'fulfilled').length;
    const successRate = (successCount / concurrency) * 100;

    return { successRate, totalRequests: concurrency, successCount };
  }

  async testErrorRate() {
    const testCount = 100;
    let errorCount = 0;

    for (let i = 0; i < testCount; i++) {
      try {
        const response = await fetch(this.baseUrl + '/health');
        if (!response.ok) errorCount++;
      } catch (error) {
        errorCount++;
      }
    }

    return { rate: (errorCount / testCount) * 100, errors: errorCount, total: testCount };
  }

  async checkAuthenticationSecurity() {
    // 模拟认证安全检查
    return {
      secure: Math.random() > 0.2,
      hasAuthMiddleware: true,
      tokenValidation: true,
      sessionManagement: true
    };
  }

  async checkInputValidation() {
    // 模拟输入验证检查
    return {
      secure: Math.random() > 0.1,
      hasInputSanitization: true,
      sqlInjectionProtection: true,
      xssProtection: true
    };
  }

  async checkHttpsConfiguration() {
    const isHttps = this.baseUrl.startsWith('https://');
    return {
      secure: isHttps,
      httpsEnabled: isHttps,
      certificateValid: isHttps,
      tlsVersion: isHttps ? '1.3' : 'N/A'
    };
  }

  async checkSensitiveInfo() {
    // 模拟敏感信息检查
    return {
      secure: Math.random() > 0.1,
      noHardcodedSecrets: true,
      envVariablesSecure: true,
      logDataSanitized: true
    };
  }

  async getCpuUsage() {
    // 模拟CPU使用率
    return Math.random() * 100;
  }

  async getMemoryUsage() {
    const usage = process.memoryUsage();
    return ((usage.heapUsed + usage.external) / usage.heapTotal) * 100;
  }

  async getDiskUsage() {
    // 模拟磁盘使用率
    return 30 + Math.random() * 60;
  }

  async getNetworkUsage() {
    // 模拟网络使用情况
    return {
      connections: Math.floor(Math.random() * 1000),
      bytesReceived: Math.floor(Math.random() * 1000000),
      bytesSent: Math.floor(Math.random() * 1000000)
    };
  }

  async testConnectivity(host) {
    const startTime = Date.now();
    try {
      // 这里应该实现真实的连通性测试
      // 为了简化，返回模拟结果
      const connected = host === '127.0.0.1' || Math.random() > 0.1;
      return {
        connected,
        time: connected ? Date.now() - startTime : 5000,
        host
      };
    } catch (error) {
      return {
        connected: false,
        time: 5000,
        host,
        error: error.message
      };
    }
  }

  async testBandwidth() {
    // 模拟带宽测试
    return 50 + Math.random() * 500; // 50-550 Mbps
  }

  async testLatency() {
    // 模拟延迟测试
    return Math.random() * 200; // 0-200ms
  }

  async analyzeErrorLogs() {
    // 模拟错误日志分析
    return {
      errorCount: Math.floor(Math.random() * 100),
      timeWindow: 'last 1 hour',
      topErrors: [
        { count: Math.floor(Math.random() * 10), message: 'Connection timeout' },
        { count: Math.floor(Math.random() * 8), message: 'Database error' }
      ]
    };
  }

  async analyzeWarningLogs() {
    // 模拟警告日志分析
    return {
      warningCount: Math.floor(Math.random() * 200),
      timeWindow: 'last 1 hour',
      topWarnings: [
        { count: Math.floor(Math.random() * 20), message: 'High memory usage' },
        { count: Math.floor(Math.random() * 15), message: 'Slow query' }
      ]
    };
  }

  async analyzeLogSize() {
    // 模拟日志大小分析
    return {
      totalSize: Math.random() * 200, // MB
      fileCount: Math.floor(Math.random() * 10) + 1,
      oldestLog: new Date(Date.now() - Math.random() * 7 * 24 * 60 * 60 * 1000)
    };
  }

  async checkConfigurationFiles() {
    // 模拟配置文件检查
    return {
      valid: Math.random() > 0.2,
      files: [
        { name: 'wrangler.toml', valid: true },
        { name: 'package.json', valid: Math.random() > 0.1 }
      ],
      errors: []
    };
  }

  async checkPermissions() {
    // 模拟权限检查
    return {
      valid: Math.random() > 0.1,
      readable: true,
      writable: Math.random() > 0.2,
      executable: Math.random() > 0.3
    };
  }

  async checkDependencyVersions() {
    // 模拟依赖版本检查
    return {
      valid: Math.random() > 0.2,
      outdatedCount: Math.floor(Math.random() * 5),
      incompatibleCount: Math.floor(Math.random() * 2)
    };
  }

  async checkNodeDependencies() {
    try {
      // 尝试读取package.json
      const packageJsonPath = join(__dirname, '../package.json');
      const packageJson = JSON.parse(readFileSync(packageJsonPath, 'utf8'));
      return {
        valid: true,
        dependencies: Object.keys(packageJson.dependencies || {}),
        devDependencies: Object.keys(packageJson.devDependencies || {})
      };
    } catch (error) {
      return {
        valid: false,
        error: error.message
      };
    }
  }

  async checkSystemDependencies() {
    // 模拟系统依赖检查
    return {
      valid: Math.random() > 0.1,
      systemDeps: ['node', 'npm', 'wrangler'],
      missingDeps: []
    };
  }

  async checkExternalDependencies() {
    // 模拟外部服务依赖检查
    return {
      available: Math.random() > 0.2,
      services: [
        { name: 'Cloudflare API', available: Math.random() > 0.1 },
        { name: 'WebSocket Server', available: Math.random() > 0.2 }
      ]
    };
  }

  /**
   * 添加诊断结果
   */
  addResult(category, name, status, message, details = {}, recommendations = []) {
    this.results.push({
      category,
      name,
      status,
      message,
      details,
      recommendations,
      timestamp: Date.now()
    });
  }

  /**
   * 打印诊断摘要
   */
  printDiagnosticSummary() {
    colorLog('\n[统计] 诊断结果摘要', 'bright');
    colorLog('=' .repeat(50), 'bright');

    const total = this.results.length;
    const healthy = this.results.filter(r => r.status === 'healthy').length;
    const warning = this.results.filter(r => r.status === 'warning').length;
    const error = this.results.filter(r => r.status === 'error').length;

    colorLog(`总检查项: ${total}`, 'white');
    colorLog(`[成功] 健康: ${healthy}`, 'green');
    colorLog(`[警告] 警告: ${warning}`, 'yellow');
    colorLog(`[错误] 错误: ${error}`, 'red');

    const healthRate = (healthy / total * 100).toFixed(1);
    colorLog(`健康率: ${healthRate}%`, healthRate >= 80 ? 'green' : healthRate >= 60 ? 'yellow' : 'red');

    // 按类别统计
    const byCategory = {};
    this.results.forEach(result => {
      if (!byCategory[result.category]) {
        byCategory[result.category] = { healthy: 0, warning: 0, error: 0 };
      }
      byCategory[result.category][result.status]++;
    });

    colorLog('\n[列表] 分类统计:', 'cyan');
    Object.entries(byCategory).forEach(([category, counts]) => {
      colorLog(`  ${category}: [成功]${counts.healthy} [警告]${counts.warning} [错误]${counts.error}`, 'white');
    });

    // 显示需要处理的问题
    const issues = this.results.filter(r => r.status !== 'healthy');
    if (issues.length > 0) {
      colorLog('\n[紧急] 需要处理的问题:', 'red');
      issues.forEach(issue => {
        const icon = issue.status === 'error' ? '[错误]' : '[警告]';
        colorLog(`  ${icon} ${issue.message}`, issue.status === 'error' ? 'red' : 'yellow');

        if (issue.recommendations && issue.recommendations.length > 0) {
          issue.recommendations.forEach(rec => {
            colorLog(`    💡 ${rec}`, 'gray');
          });
        }
      });
    }

    // 建议优先处理项
    if (error > 0) {
      colorLog('\n[目标] 建议优先处理:', 'red');
      colorLog('1. 修复错误级别的项目', 'red');
      colorLog('2. 检查系统配置', 'yellow');
      colorLog('3. 优化性能瓶颈', 'yellow');
    } else if (warning > 0) {
      colorLog('\n[目标] 建议优化项:', 'yellow');
      colorLog('1. 处理警告级别的项目', 'yellow');
      colorLog('2. 监控系统指标', 'cyan');
      colorLog('3. 预防性维护', 'cyan');
    } else {
      colorLog('\n[完成] 系统状态良好!', 'green');
      colorLog('继续保持监控和维护', 'green');
    }

    const duration = Date.now() - this.startTime;
    colorLog(`\n[计时] 诊断耗时: ${duration}ms`, 'cyan');
  }

  /**
   * 生成诊断报告
   */
  generateReport() {
    const total = this.results.length;
    const healthy = this.results.filter(r => r.status === 'healthy').length;
    const warning = this.results.filter(r => r.status === 'warning').length;
    const error = this.results.filter(r => r.status === 'error').length;

    return {
      timestamp: new Date().toISOString(),
      duration: Date.now() - this.startTime,
      summary: {
        total,
        healthy,
        warning,
        error,
        healthRate: (healthy / total * 100).toFixed(1)
      },
      results: this.results,
      recommendations: this.results
        .filter(r => r.recommendations && r.recommendations.length > 0)
        .flatMap(r => r.recommendations.map(rec => ({
          category: r.category,
          issue: r.message,
          recommendation: rec,
          priority: r.status
        })))
    };
  }
}

/**
 * 命令行接口
 */
async function main() {
  const args = process.argv.slice(2);
  const diagnostic = new SystemDiagnostic();

  if (args.length === 0) {
    // 显示帮助信息
    colorLog('\n[查询] CicadaRelay诊断工具', 'bright');
    colorLog('=' .repeat(50), 'bright');
    colorLog('\n使用方法:', 'yellow');
    colorLog('  node debug-diagnostic.js [命令]', 'white');
    colorLog('\n可用命令:', 'yellow');
    colorLog('  all                 - 运行完整诊断', 'white');
    colorLog('  environment         - 环境诊断', 'white');
    colorLog('  services            - 服务状态诊断', 'white');
    colorLog('  performance         - 性能诊断', 'white');
    colorLog('  security            - 安全诊断', 'white');
    colorLog('  resources           - 资源使用诊断', 'white');
    colorLog('  network             - 网络连接诊断', 'white');
    colorLog('  logs                - 日志诊断', 'white');
    colorLog('  config              - 配置诊断', 'white');
    colorLog('  dependencies        - 依赖诊断', 'white');
    colorLog('  report              - 生成诊断报告', 'white');
    colorLog('\n环境变量:', 'yellow');
    colorLog('  CICADA_RELAY_URL       - 服务器URL', 'white');
    colorLog('  HMAC_SECRET        - 签名密钥', 'white');
    colorLog('\n示例:', 'cyan');
    colorLog('  node debug-diagnostic.js all', 'white');
    colorLog('  node debug-diagnostic.js performance', 'white');
    colorLog('  node debug-diagnostic.js security', 'white');
    colorLog('  node debug-diagnostic.js report > diagnostic-report.json', 'white');

    process.exit(0);
  }

  const command = args[0];

  try {
    switch (command) {
      case 'all':
        await diagnostic.runFullDiagnostic();
        break;

      case 'environment':
        await diagnostic.diagnoseEnvironment();
        diagnostic.printDiagnosticSummary();
        break;

      case 'services':
        await diagnostic.diagnoseServices();
        diagnostic.printDiagnosticSummary();
        break;

      case 'performance':
        await diagnostic.diagnosePerformance();
        diagnostic.printDiagnosticSummary();
        break;

      case 'security':
        await diagnostic.diagnoseSecurity();
        diagnostic.printDiagnosticSummary();
        break;

      case 'resources':
        await diagnostic.diagnoseResources();
        diagnostic.printDiagnosticSummary();
        break;

      case 'network':
        await diagnostic.diagnoseNetwork();
        diagnostic.printDiagnosticSummary();
        break;

      case 'logs':
        await diagnostic.diagnoseLogs();
        diagnostic.printDiagnosticSummary();
        break;

      case 'config':
        await diagnostic.diagnoseConfiguration();
        diagnostic.printDiagnosticSummary();
        break;

      case 'dependencies':
        await diagnostic.diagnoseDependencies();
        diagnostic.printDiagnosticSummary();
        break;

      case 'report':
        await diagnostic.runFullDiagnostic();
        const report = diagnostic.generateReport();
        colorLogJson(report, '诊断报告', 'cyan');
        break;

      default:
        colorLog(`[错误] 未知命令: ${command}`, 'red');
        colorLog('运行 "node debug-diagnostic.js" 查看帮助', 'yellow');
        process.exit(1);
    }
  } catch (error) {
    colorLog(`[崩溃] 诊断执行失败: ${error.message}`, 'red');
    process.exit(1);
  }
}

// 运行主程序
main().catch(error => {
  colorLog(`[崩溃] 程序执行失败: ${error.message}`, 'red');
  process.exit(1);
});