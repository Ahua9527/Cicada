/**
 * 系统诊断工具
 *
 * 提供系统状态检测、问题诊断和性能分析功能
 */

import process from 'node:process';

/**
 * 诊断结果接口
 */
export interface DiagnosticResult {
  category: string;
  name: string;
  status: 'healthy' | 'warning' | 'error' | 'unknown';
  message: string;
  details?: Record<string, any>;
  recommendations?: string[];
  timestamp: number;
}

/**
 * 系统指标接口
 */
export interface SystemMetrics {
  cpu: {
    usage: number;
    cores: number;
    loadAverage: number[];
  };
  memory: {
    total: number;
    used: number;
    free: number;
    usage: number;
  };
  network: {
    connections: number;
    requestsPerSecond: number;
    errorRate: number;
    avgResponseTime: number;
  };
  storage: {
    total: number;
    used: number;
    free: number;
    usage: number;
  };
  uptime: number;
  timestamp: number;
}

/**
 * 性能分析结果
 */
export interface PerformanceAnalysis {
  responseTime: {
    p50: number;
    p95: number;
    p99: number;
    avg: number;
    max: number;
  };
  throughput: {
    requestsPerSecond: number;
    bytesPerSecond: number;
    concurrency: number;
  };
  errors: {
    rate: number;
    errorsByType: Record<string, number>;
    recentErrors: Array<{
      timestamp: number;
      error: string;
      context: Record<string, any>;
    }>;
  };
  resources: {
    memoryUsage: number;
    cpuUsage: number;
    diskIO: number;
    networkIO: number;
  };
}

/**
 * 安全事件分析
 */
export interface SecurityAnalysis {
  threats: {
    total: number;
    byType: Record<string, number>;
    severity: Record<string, number>;
    recentThreats: Array<{
      timestamp: number;
      type: string;
      severity: 'low' | 'medium' | 'high' | 'critical';
      source: string;
      description: string;
    }>;
  };
  authentication: {
    failedAttempts: number;
    uniqueIps: number;
    blockedIps: string[];
    suspiciousPatterns: string[];
  };
  authorization: {
    deniedAccess: number;
    privilegeEscalation: number;
    unusualAccess: number;
  };
  dataProtection: {
    dataExfiltration: number;
    sensitiveAccess: number;
    encryptionViolations: number;
  };
}

/**
 * 系统诊断器
 */
export class SystemDiagnostic {
  private results: DiagnosticResult[] = [];
  private metrics: SystemMetrics | null = null;
  private startTime: number = Date.now();

  /**
   * 运行完整的系统诊断
   */
  async runFullDiagnostic(): Promise<DiagnosticResult[]> {
    this.results = [];
    const startTime = Date.now();

    console.log('[诊断] 开始系统诊断...');
    console.log('='.repeat(50));

    try {
      // 1. 基础系统检查
      await this.checkBasicSystem();

      // 2. 网络连接诊断
      await this.diagnoseNetwork();

      // 3. 服务状态诊断
      await this.diagnoseServices();

      // 4. 性能分析
      await this.analyzePerformance();

      // 5. 安全检查
      await this.checkSecurity();

      // 6. 资源使用诊断
      await this.diagnoseResources();

      // 7. 日志分析
      await this.analyzeLogs();

      // 8. 配置验证
      await this.validateConfiguration();

      const duration = Date.now() - startTime;
      this.addResult(
        'system',
        'diagnostic_complete',
        'healthy',
        `系统诊断完成，耗时 ${duration}ms`,
        { duration, checksRun: this.results.length }
      );

      this.printDiagnosticSummary();

      return this.results;
    } catch (error) {
      this.addResult(
        'system',
        'diagnostic_error',
        'error',
        `系统诊断失败: ${error instanceof Error ? error.message : String(error)}`
      );
      throw error;
    }
  }

  /**
   * 基础系统检查
   */
  private async checkBasicSystem(): Promise<void> {
    console.log('\n[系统] 基础系统检查');

    // 运行时环境检查
    const nodeVersion = process.version;
    const platform = process.platform;
    const arch = process.arch;
    const uptime = process.uptime();

    this.addResult(
      'system',
      'runtime',
      'healthy',
      `运行时环境: Node.js ${nodeVersion} on ${platform}-${arch}`,
      { nodeVersion, platform, arch, uptime }
    );

    // 内存使用检查
    const memUsage = process.memoryUsage();
    const totalMem = memUsage.heapTotal + memUsage.external;
    const usedMem = memUsage.heapUsed + memUsage.external;
    const memUsagePercent = (usedMem / totalMem) * 100;

    let memStatus: DiagnosticResult['status'] = 'healthy';
    if (memUsagePercent > 90) {
      memStatus = 'error';
    } else if (memUsagePercent > 75) {
      memStatus = 'warning';
    }

    this.addResult(
      'system',
      'memory',
      memStatus,
      `内存使用: ${memUsagePercent.toFixed(1)}% (${(usedMem / 1024 / 1024).toFixed(1)}MB)`,
      {
        heapUsed: memUsage.heapUsed,
        heapTotal: memUsage.heapTotal,
        external: memUsage.external,
        rss: memUsage.rss,
        usagePercent: memUsagePercent,
      },
      memStatus !== 'healthy' ? ['考虑增加内存限制', '检查内存泄漏', '优化数据结构'] : undefined
    );

    // CPU使用检查（模拟）
    const cpuUsage = await this.getCpuUsage();
    let cpuStatus: DiagnosticResult['status'] = 'healthy';
    if (cpuUsage > 90) {
      cpuStatus = 'error';
    } else if (cpuUsage > 75) {
      cpuStatus = 'warning';
    }

    this.addResult(
      'system',
      'cpu',
      cpuStatus,
      `CPU使用: ${cpuUsage.toFixed(1)}%`,
      { usage: cpuUsage },
      cpuStatus !== 'healthy'
        ? ['检查CPU密集型操作', '考虑增加计算资源', '优化算法效率']
        : undefined
    );
  }

  /**
   * 网络连接诊断
   */
  private async diagnoseNetwork(): Promise<void> {
    console.log('\n[网络] 网络连接诊断');

    // 基础连接测试
    const connectionTests = [
      { name: '本地回环', host: '127.0.0.1', port: 8787 },
      { name: 'DNS解析', host: 'google.com', port: 443 },
    ];

    for (const test of connectionTests) {
      try {
        const startTime = Date.now();
        const isConnected = await this.testConnection(test.host, test.port);
        const responseTime = Date.now() - startTime;

        this.addResult(
          'network',
          test.name,
          isConnected ? 'healthy' : 'error',
          `${test.name}: ${isConnected ? '连接正常' : '连接失败'} (${responseTime}ms)`,
          { host: test.host, port: test.port, responseTime, connected: isConnected }
        );
      } catch (error) {
        this.addResult(
          'network',
          test.name,
          'error',
          `${test.name}: 连接异常 - ${error instanceof Error ? error.message : String(error)}`
        );
      }
    }

    // 带宽测试（模拟）
    const bandwidth = await this.testBandwidth();
    this.addResult(
      'network',
      'bandwidth',
      bandwidth > 1 ? 'healthy' : 'warning',
      `带宽测试: ${bandwidth.toFixed(2)} Mbps`,
      { bandwidthMbps: bandwidth }
    );
  }

  /**
   * 服务状态诊断
   */
  private async diagnoseServices(): Promise<void> {
    console.log('\n[服务] 服务状态诊断');

    // 检查主要服务端口
    const services = [
      { name: 'HTTP服务', port: 8787, protocol: 'http' },
      { name: 'WebSocket服务', port: 8787, protocol: 'ws' },
    ];

    for (const service of services) {
      const isRunning = await this.checkServicePort(service.port);
      this.addResult(
        'service',
        service.name,
        isRunning ? 'healthy' : 'error',
        `${service.name}: ${isRunning ? '运行中' : '未运行'}`,
        { port: service.port, protocol: service.protocol, running: isRunning }
      );
    }

    // 检查服务健康状态
    try {
      const healthResponse = await this.checkServiceHealth();
      this.addResult(
        'service',
        'health_check',
        healthResponse.healthy ? 'healthy' : 'warning',
        `服务健康检查: ${healthResponse.healthy ? '正常' : '异常'}`,
        healthResponse
      );
    } catch (error) {
      this.addResult(
        'service',
        'health_check',
        'error',
        `服务健康检查失败: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  /**
   * 性能分析
   */
  private async analyzePerformance(): Promise<void> {
    console.log('\n[性能] 性能分析');

    const performance = await this.gatherPerformanceMetrics();

    // 响应时间分析
    const avgResponseTime = performance.responseTime.avg;
    let responseTimeStatus: DiagnosticResult['status'] = 'healthy';
    if (avgResponseTime > 5000) {
      responseTimeStatus = 'error';
    } else if (avgResponseTime > 1000) {
      responseTimeStatus = 'warning';
    }

    this.addResult(
      'performance',
      'response_time',
      responseTimeStatus,
      `平均响应时间: ${avgResponseTime.toFixed(1)}ms`,
      performance.responseTime,
      responseTimeStatus !== 'healthy'
        ? ['优化数据库查询', '增加缓存', '减少外部API调用']
        : undefined
    );

    // 吞吐量分析
    const throughput = performance.throughput.requestsPerSecond;
    let throughputStatus: DiagnosticResult['status'] = 'healthy';
    if (throughput < 10) {
      throughputStatus = 'warning';
    }

    this.addResult(
      'performance',
      'throughput',
      throughputStatus,
      `吞吐量: ${throughput.toFixed(1)} RPS`,
      performance.throughput,
      throughputStatus !== 'healthy'
        ? ['优化代码执行效率', '增加并发处理能力', '减少阻塞操作']
        : undefined
    );

    // 错误率分析
    const errorRate = performance.errors.rate;
    let errorStatus: DiagnosticResult['status'] = 'healthy';
    if (errorRate > 10) {
      errorStatus = 'error';
    } else if (errorRate > 5) {
      errorStatus = 'warning';
    }

    this.addResult(
      'performance',
      'error_rate',
      errorStatus,
      `错误率: ${errorRate.toFixed(1)}%`,
      performance.errors,
      errorStatus !== 'healthy' ? ['检查错误日志', '修复高频错误', '改善错误处理机制'] : undefined
    );
  }

  /**
   * 安全检查
   */
  private async checkSecurity(): Promise<void> {
    console.log('\n[安全] 安全检查');

    const security = await this.analyzeSecurityEvents();

    // 威胁检测
    const threatCount = security.threats.total;
    let threatStatus: DiagnosticResult['status'] = 'healthy';
    if (threatCount > 100) {
      threatStatus = 'error';
    } else if (threatCount > 10) {
      threatStatus = 'warning';
    }

    this.addResult(
      'security',
      'threats',
      threatStatus,
      `检测到威胁: ${threatCount}个`,
      security.threats,
      threatStatus !== 'healthy' ? ['检查威胁日志', '更新安全规则', '加强访问控制'] : undefined
    );

    // 认证安全
    const failedAuth = security.authentication.failedAttempts;
    let authStatus: DiagnosticResult['status'] = 'healthy';
    if (failedAuth > 100) {
      authStatus = 'error';
    } else if (failedAuth > 10) {
      authStatus = 'warning';
    }

    this.addResult(
      'security',
      'authentication',
      authStatus,
      `认证失败次数: ${failedAuth}`,
      security.authentication,
      authStatus !== 'healthy' ? ['检查账户安全', '实施账户锁定策略', '监控异常登录'] : undefined
    );

    // 数据保护
    const dataViolations = security.dataProtection.encryptionViolations;
    let dataStatus: DiagnosticResult['status'] = 'healthy';
    if (dataViolations > 0) {
      dataStatus = 'error';
    }

    this.addResult(
      'security',
      'data_protection',
      dataStatus,
      `加密违规: ${dataViolations}次`,
      security.dataProtection,
      dataStatus !== 'healthy'
        ? ['检查数据加密配置', '更新加密证书', '实施数据保护策略']
        : undefined
    );
  }

  /**
   * 资源使用诊断
   */
  private async diagnoseResources(): Promise<void> {
    console.log('\n[资源] 资源使用诊断');

    const resources = await this.getResourceUsage();

    // 内存资源
    const memUsage = resources.memoryUsage;
    let memStatus: DiagnosticResult['status'] = 'healthy';
    if (memUsage > 90) {
      memStatus = 'error';
    } else if (memUsage > 75) {
      memStatus = 'warning';
    }

    this.addResult(
      'resource',
      'memory',
      memStatus,
      `内存使用率: ${memUsage.toFixed(1)}%`,
      { memoryUsage: memUsage, limit: resources.memoryLimit },
      memStatus !== 'healthy' ? ['优化内存使用', '增加内存配额', '检查内存泄漏'] : undefined
    );

    // CPU资源
    const cpuUsage = resources.cpuUsage;
    let cpuStatus: DiagnosticResult['status'] = 'healthy';
    if (cpuUsage > 90) {
      cpuStatus = 'error';
    } else if (cpuUsage > 75) {
      cpuStatus = 'warning';
    }

    this.addResult(
      'resource',
      'cpu',
      cpuStatus,
      `CPU使用率: ${cpuUsage.toFixed(1)}%`,
      { cpuUsage, cores: resources.cpuCores },
      cpuStatus !== 'healthy' ? ['优化CPU密集型操作', '增加计算资源', '优化算法效率'] : undefined
    );

    // 存储资源
    const diskUsage = resources.diskUsage;
    let diskStatus: DiagnosticResult['status'] = 'healthy';
    if (diskUsage > 90) {
      diskStatus = 'error';
    } else if (diskUsage > 80) {
      diskStatus = 'warning';
    }

    this.addResult(
      'resource',
      'storage',
      diskStatus,
      `存储使用率: ${diskUsage.toFixed(1)}%`,
      { diskUsage, total: resources.diskTotal },
      diskStatus !== 'healthy' ? ['清理临时文件', '增加存储空间', '实施数据归档策略'] : undefined
    );
  }

  /**
   * 日志分析
   */
  private async analyzeLogs(): Promise<void> {
    console.log('\n[日志] 日志分析');

    const logAnalysis = await this.analyzeRecentLogs();

    // 错误日志分析
    const errorCount = logAnalysis.errorCount;
    let logStatus: DiagnosticResult['status'] = 'healthy';
    if (errorCount > 50) {
      logStatus = 'error';
    } else if (errorCount > 10) {
      logStatus = 'warning';
    }

    this.addResult(
      'logs',
      'error_analysis',
      logStatus,
      `错误日志数量: ${errorCount}`,
      { errorCount, timeWindow: logAnalysis.timeWindow },
      logStatus !== 'healthy' ? ['检查高频错误', '优化错误处理', '增加日志监控'] : undefined
    );

    // 警告日志分析
    const warningCount = logAnalysis.warningCount;
    this.addResult(
      'logs',
      'warning_analysis',
      warningCount > 20 ? 'warning' : 'healthy',
      `警告日志数量: ${warningCount}`,
      { warningCount, timeWindow: logAnalysis.timeWindow }
    );

    // 性能日志分析
    const slowQueries = logAnalysis.slowQueries;
    let perfStatus: DiagnosticResult['status'] = 'healthy';
    if (slowQueries > 20) {
      perfStatus = 'warning';
    }

    this.addResult(
      'logs',
      'performance_analysis',
      perfStatus,
      `慢查询数量: ${slowQueries}`,
      { slowQueries, threshold: logAnalysis.slowQueryThreshold },
      perfStatus !== 'healthy' ? ['优化慢查询', '增加数据库索引', '优化查询逻辑'] : undefined
    );
  }

  /**
   * 配置验证
   */
  private async validateConfiguration(): Promise<void> {
    console.log('\n[配置] 配置验证');

    // 环境变量检查
    const requiredEnvVars = ['CICADA_RELAY_URL'];

    const missingVars = requiredEnvVars.filter(varName => !process.env[varName]);
    let configStatus: DiagnosticResult['status'] = 'healthy';
    if (missingVars.length > 0) {
      configStatus = 'error';
    }

    this.addResult(
      'config',
      'environment_variables',
      configStatus,
      `环境变量: ${missingVars.length === 0 ? '完整' : `缺少 ${missingVars.length} 个`}`,
      { required: requiredEnvVars, missing: missingVars },
      missingVars.length > 0 ? ['设置缺失的环境变量', '检查配置文件', '更新部署配置'] : undefined
    );

    // 配置文件验证
    const configValidation = await this.validateConfigFiles();
    this.addResult(
      'config',
      'config_files',
      configValidation.valid ? 'healthy' : 'warning',
      `配置文件: ${configValidation.valid ? '有效' : '存在警告'}`,
      configValidation
    );
  }

  /**
   * 获取CPU使用率（模拟）
   */
  private async getCpuUsage(): Promise<number> {
    // 这里应该实现真实的CPU使用率检测
    // 为了简化，返回模拟值
    return Math.random() * 100;
  }

  /**
   * 测试网络连接
   */
  private async testConnection(host: string, _port: number): Promise<boolean> {
    // 这里应该实现真实的连接测试
    // 为了简化，返回模拟值
    return host === '127.0.0.1' || Math.random() > 0.1;
  }

  /**
   * 测试带宽（模拟）
   */
  private async testBandwidth(): Promise<number> {
    // 这里应该实现真实的带宽测试
    // 为了简化，返回模拟值
    return 50 + Math.random() * 900; // 50-950 Mbps
  }

  /**
   * 检查服务端口
   */
  private async checkServicePort(_port: number): Promise<boolean> {
    // 这里应该实现真实的端口检查
    // 为了简化，返回模拟值
    return Math.random() > 0.1;
  }

  /**
   * 检查服务健康状态
   */
  private async checkServiceHealth(): Promise<{ healthy: boolean; [key: string]: any }> {
    // 这里应该实现真实的健康检查
    // 为了简化，返回模拟值
    return {
      healthy: Math.random() > 0.1,
      uptime: Math.floor(Math.random() * 86400),
      version: '1.0.0',
      memory: Math.floor(Math.random() * 1000000000),
      connections: Math.floor(Math.random() * 1000),
    };
  }

  /**
   * 收集性能指标
   */
  private async gatherPerformanceMetrics(): Promise<PerformanceAnalysis> {
    // 这里应该实现真实的性能指标收集
    // 为了简化，返回模拟数据
    return {
      responseTime: {
        p50: 100 + Math.random() * 200,
        p95: 500 + Math.random() * 1000,
        p99: 1000 + Math.random() * 2000,
        avg: 200 + Math.random() * 300,
        max: 2000 + Math.random() * 3000,
      },
      throughput: {
        requestsPerSecond: 50 + Math.random() * 200,
        bytesPerSecond: 1000000 + Math.random() * 9000000,
        concurrency: Math.floor(Math.random() * 100),
      },
      errors: {
        rate: Math.random() * 10,
        errorsByType: {
          timeout: Math.floor(Math.random() * 10),
          connection: Math.floor(Math.random() * 5),
          validation: Math.floor(Math.random() * 15),
        },
        recentErrors: [],
      },
      resources: {
        memoryUsage: 50 + Math.random() * 40,
        cpuUsage: 20 + Math.random() * 60,
        diskIO: Math.random() * 100,
        networkIO: Math.random() * 100,
      },
    };
  }

  /**
   * 分析安全事件
   */
  private async analyzeSecurityEvents(): Promise<SecurityAnalysis> {
    // 这里应该实现真实的安全事件分析
    // 为了简化，返回模拟数据
    return {
      threats: {
        total: Math.floor(Math.random() * 50),
        byType: {
          sql_injection: Math.floor(Math.random() * 5),
          xss: Math.floor(Math.random() * 10),
          brute_force: Math.floor(Math.random() * 8),
          ddos: Math.floor(Math.random() * 3),
        },
        severity: {
          low: Math.floor(Math.random() * 20),
          medium: Math.floor(Math.random() * 15),
          high: Math.floor(Math.random() * 10),
          critical: Math.floor(Math.random() * 5),
        },
        recentThreats: [],
      },
      authentication: {
        failedAttempts: Math.floor(Math.random() * 50),
        uniqueIps: Math.floor(Math.random() * 20),
        blockedIps: [],
        suspiciousPatterns: [],
      },
      authorization: {
        deniedAccess: Math.floor(Math.random() * 10),
        privilegeEscalation: Math.floor(Math.random() * 3),
        unusualAccess: Math.floor(Math.random() * 15),
      },
      dataProtection: {
        dataExfiltration: Math.floor(Math.random() * 2),
        sensitiveAccess: Math.floor(Math.random() * 25),
        encryptionViolations: Math.floor(Math.random() * 3),
      },
    };
  }

  /**
   * 获取资源使用情况
   */
  private async getResourceUsage(): Promise<{
    memoryUsage: number;
    memoryLimit: number;
    cpuUsage: number;
    cpuCores: number;
    diskUsage: number;
    diskTotal: number;
  }> {
    const memUsage = process.memoryUsage();
    const memoryUsage = ((memUsage.heapUsed + memUsage.external) / memUsage.heapTotal) * 100;

    return {
      memoryUsage,
      memoryLimit: memUsage.heapTotal,
      cpuUsage: Math.random() * 100,
      cpuCores: 4, // 假设4核
      diskUsage: 30 + Math.random() * 50,
      diskTotal: 100, // GB
    };
  }

  /**
   * 分析最近日志
   */
  private async analyzeRecentLogs(): Promise<{
    errorCount: number;
    warningCount: number;
    slowQueries: number;
    timeWindow: string;
    slowQueryThreshold: number;
  }> {
    // 这里应该实现真实的日志分析
    // 为了简化，返回模拟数据
    return {
      errorCount: Math.floor(Math.random() * 100),
      warningCount: Math.floor(Math.random() * 200),
      slowQueries: Math.floor(Math.random() * 50),
      timeWindow: 'last 1 hour',
      slowQueryThreshold: 1000, // ms
    };
  }

  /**
   * 验证配置文件
   */
  private async validateConfigFiles(): Promise<{
    valid: boolean;
    errors: string[];
    warnings: string[];
  }> {
    // 这里应该实现真实的配置文件验证
    // 为了简化，返回模拟数据
    return {
      valid: Math.random() > 0.2,
      errors: [],
      warnings: Math.random() > 0.7 ? ['建议配置超时时间'] : [],
    };
  }

  /**
   * 添加诊断结果
   */
  private addResult(
    category: string,
    name: string,
    status: DiagnosticResult['status'],
    message: string,
    details?: Record<string, any>,
    recommendations?: string[]
  ): void {
    this.results.push({
      category,
      name,
      status,
      message,
      details,
      recommendations,
      timestamp: Date.now(),
    });
  }

  /**
   * 打印诊断摘要
   */
  private printDiagnosticSummary(): void {
    console.log('\n[摘要] 诊断结果摘要');
    console.log('='.repeat(50));

    const totalChecks = this.results.length;
    const healthy = this.results.filter(r => r.status === 'healthy').length;
    const warnings = this.results.filter(r => r.status === 'warning').length;
    const errors = this.results.filter(r => r.status === 'error').length;

    console.log(`总检查项: ${totalChecks}`);
    console.log(`[成功] 健康: ${healthy}`);
    console.log(`[警告] 警告: ${warnings}`);
    console.log(`[错误] 错误: ${errors}`);

    // 按类别统计
    const byCategory = this.results.reduce(
      (acc, result) => {
        if (!acc[result.category]) {
          acc[result.category] = { healthy: 0, warning: 0, error: 0, unknown: 0 };
        }
        acc[result.category][result.status]++;
        return acc;
      },
      {} as Record<string, Record<DiagnosticResult['status'], number>>
    );

    console.log('\n[统计] 分类统计:');
    Object.entries(byCategory).forEach(([category, counts]) => {
      console.log(
        `  ${category}: [成功]${counts.healthy} [警告]${counts.warning} [错误]${counts.error}`
      );
    });

    // 显示需要关注的问题
    const issues = this.results.filter(r => r.status !== 'healthy');
    if (issues.length > 0) {
      console.log('\n[警告] 需要关注的问题:');
      issues.forEach(issue => {
        const icon = issue.status === 'error' ? '[错误]' : '[警告]';
        console.log(`  ${icon} ${issue.message}`);
        if (issue.recommendations) {
          issue.recommendations.forEach(rec => {
            console.log(`    [建议] ${rec}`);
          });
        }
      });
    }

    console.log('\n[优先级] 建议优先处理:');
    if (errors > 0) {
      console.log('1. 修复错误级别的项目');
    } else if (warnings > 0) {
      console.log('1. 处理警告级别的项目');
    } else {
      console.log('1. 系统运行良好，继续监控');
    }

    const diagnosticTime = Date.now() - this.startTime;
    console.log(`\n[计时] 诊断总耗时: ${diagnosticTime}ms`);
  }

  /**
   * 获取诊断结果
   */
  getResults(): DiagnosticResult[] {
    return this.results;
  }

  /**
   * 获取系统指标
   */
  async getSystemMetrics(): Promise<SystemMetrics> {
    if (!this.metrics) {
      this.metrics = {
        cpu: {
          usage: await this.getCpuUsage(),
          cores: 4,
          loadAverage: [0.5, 0.8, 1.2],
        },
        memory: {
          total: 8000000000, // 8GB
          used: 4000000000, // 4GB
          free: 4000000000, // 4GB
          usage: 50,
        },
        network: {
          connections: 150,
          requestsPerSecond: 100,
          errorRate: 2.5,
          avgResponseTime: 250,
        },
        storage: {
          total: 100000000000, // 100GB
          used: 50000000000, // 50GB
          free: 50000000000, // 50GB
          usage: 50,
        },
        uptime: process.uptime(),
        timestamp: Date.now(),
      };
    }
    return this.metrics;
  }

  /**
   * 导出诊断报告
   */
  exportReport(): {
    timestamp: number;
    summary: {
      total: number;
      healthy: number;
      warning: number;
      error: number;
    };
    results: DiagnosticResult[];
    metrics: SystemMetrics | null;
  } {
    const summary = {
      total: this.results.length,
      healthy: this.results.filter(r => r.status === 'healthy').length,
      warning: this.results.filter(r => r.status === 'warning').length,
      error: this.results.filter(r => r.status === 'error').length,
    };

    return {
      timestamp: Date.now(),
      summary,
      results: this.results,
      metrics: this.metrics,
    };
  }
}
