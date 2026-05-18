/**
 * 性能分析器
 *
 * 提供详细的性能分析、瓶颈识别和优化建议
 */

/**
 * 性能指标接口
 */
export interface PerformanceMetrics {
  timestamp: number;
  responseTime: {
    min: number;
    max: number;
    avg: number;
    p50: number;
    p90: number;
    p95: number;
    p99: number;
  };
  throughput: {
    requestsPerSecond: number;
    bytesPerSecond: number;
    activeConnections: number;
  };
  errorRate: {
    total: number;
    rate: number;
    errorsByType: Record<string, number>;
  };
  resources: {
    cpuUsage: number;
    memoryUsage: number;
    diskIO: number;
    networkIO: number;
  };
  cache: {
    hitRate: number;
    missRate: number;
    size: number;
  };
  database: {
    connectionPool: {
      active: number;
      idle: number;
      total: number;
    };
    queryTime: {
      avg: number;
      slow: number;
    };
  };
}

/**
 * 性能瓶颈
 */
export interface PerformanceBottleneck {
  category: 'response_time' | 'throughput' | 'resource' | 'error' | 'database' | 'cache';
  severity: 'low' | 'medium' | 'high' | 'critical';
  description: string;
  impact: string;
  recommendations: string[];
  metrics: Record<string, number>;
  timestamp: number;
}

/**
 * 性能趋势
 */
export interface PerformanceTrend {
  metric: string;
  timeframe: string;
  trend: 'improving' | 'degrading' | 'stable';
  changePercent: number;
  dataPoints: Array<{
    timestamp: number;
    value: number;
  }>;
}

/**
 * 性能分析器
 */
export class PerformanceAnalyzer {
  private metricsHistory: PerformanceMetrics[] = [];
  private bottlenecks: PerformanceBottleneck[] = [];
  private baselines: Map<string, number> = new Map();
  private maxHistorySize = 1000;

  constructor() {
    this.initializeBaselines();
  }

  /**
   * 初始化性能基准
   */
  private initializeBaselines(): void {
    this.baselines.set('avgResponseTime', 500); // 500ms
    this.baselines.set('p95ResponseTime', 1000); // 1000ms
    this.baselines.set('requestsPerSecond', 100); // 100 RPS
    this.baselines.set('errorRate', 1); // 1%
    this.baselines.set('cpuUsage', 70); // 70%
    this.baselines.set('memoryUsage', 80); // 80%
    this.baselines.set('cacheHitRate', 90); // 90%
  }

  /**
   * 记录性能指标
   */
  recordMetrics(metrics: PerformanceMetrics): void {
    this.metricsHistory.push(metrics);

    // 限制历史数据大小
    if (this.metricsHistory.length > this.maxHistorySize) {
      this.metricsHistory.shift();
    }

    // 分析当前指标
    this.analyzeMetrics(metrics);
  }

  /**
   * 分析性能指标
   */
  private analyzeMetrics(metrics: PerformanceMetrics): void {
    this.bottlenecks = [];

    // 分析响应时间
    this.analyzeResponseTime(metrics);

    // 分析吞吐量
    this.analyzeThroughput(metrics);

    // 分析错误率
    this.analyzeErrorRate(metrics);

    // 分析资源使用
    this.analyzeResourceUsage(metrics);

    // 分析缓存性能
    this.analyzeCachePerformance(metrics);

    // 分析数据库性能
    this.analyzeDatabasePerformance(metrics);
  }

  /**
   * 分析响应时间
   */
  private analyzeResponseTime(metrics: PerformanceMetrics): void {
    const { responseTime } = metrics;
    const baseline = this.baselines.get('avgResponseTime') ?? 500;
    const p95Baseline = this.baselines.get('p95ResponseTime') ?? 1000;

    // 平均响应时间分析
    if (responseTime.avg > baseline * 2) {
      this.bottlenecks.push({
        category: 'response_time',
        severity: 'critical',
        description: `平均响应时间过高: ${responseTime.avg.toFixed(1)}ms`,
        impact: '严重影响用户体验，可能导致请求超时',
        recommendations: [
          '检查慢查询和复杂业务逻辑',
          '优化数据库查询和索引',
          '增加缓存策略',
          '考虑异步处理耗时操作',
          '增加服务器资源',
        ],
        metrics: { avgResponseTime: responseTime.avg, baseline },
        timestamp: Date.now(),
      });
    } else if (responseTime.avg > baseline * 1.5) {
      this.bottlenecks.push({
        category: 'response_time',
        severity: 'high',
        description: `平均响应时间偏高: ${responseTime.avg.toFixed(1)}ms`,
        impact: '影响用户体验，需要优化',
        recommendations: ['优化代码执行效率', '检查外部API调用', '优化数据处理逻辑'],
        metrics: { avgResponseTime: responseTime.avg, baseline },
        timestamp: Date.now(),
      });
    }

    // P95响应时间分析
    if (responseTime.p95 > p95Baseline * 2) {
      this.bottlenecks.push({
        category: 'response_time',
        severity: 'high',
        description: `P95响应时间过高: ${responseTime.p95.toFixed(1)}ms`,
        impact: '大部分用户响应时间过长',
        recommendations: ['识别并优化慢请求路径', '实施请求超时和熔断机制', '优化数据库连接池'],
        metrics: { p95ResponseTime: responseTime.p95, baseline: p95Baseline },
        timestamp: Date.now(),
      });
    }

    // 响应时间方差分析
    const variance = responseTime.max - responseTime.min;
    if (variance > responseTime.avg * 3) {
      this.bottlenecks.push({
        category: 'response_time',
        severity: 'medium',
        description: `响应时间不稳定，方差过大: ${variance.toFixed(1)}ms`,
        impact: '性能不稳定，用户体验不一致',
        recommendations: ['检查性能波动的原因', '优化资源分配策略', '实施负载均衡'],
        metrics: { variance, avgResponseTime: responseTime.avg },
        timestamp: Date.now(),
      });
    }
  }

  /**
   * 分析吞吐量
   */
  private analyzeThroughput(metrics: PerformanceMetrics): void {
    const { throughput } = metrics;
    const baseline = this.baselines.get('requestsPerSecond') ?? 100;

    if (throughput.requestsPerSecond < baseline * 0.5) {
      this.bottlenecks.push({
        category: 'throughput',
        severity: 'high',
        description: `吞吐量过低: ${throughput.requestsPerSecond.toFixed(1)} RPS`,
        impact: '系统处理能力不足，无法满足负载需求',
        recommendations: [
          '优化代码执行效率',
          '增加并发处理能力',
          '扩展服务器资源',
          '优化数据库连接池',
          '减少同步阻塞操作',
        ],
        metrics: { requestsPerSecond: throughput.requestsPerSecond, baseline },
        timestamp: Date.now(),
      });
    } else if (throughput.requestsPerSecond < baseline * 0.8) {
      this.bottlenecks.push({
        category: 'throughput',
        severity: 'medium',
        description: `吞吐量偏低: ${throughput.requestsPerSecond.toFixed(1)} RPS`,
        impact: '系统处理能力有提升空间',
        recommendations: ['分析和优化性能瓶颈', '调整并发处理策略', '优化资源使用效率'],
        metrics: { requestsPerSecond: throughput.requestsPerSecond, baseline },
        timestamp: Date.now(),
      });
    }

    // 连接数分析
    if (throughput.activeConnections > 1000) {
      this.bottlenecks.push({
        category: 'throughput',
        severity: 'medium',
        description: `活跃连接数过多: ${throughput.activeConnections}`,
        impact: '可能导致资源耗尽和连接问题',
        recommendations: ['实施连接池管理', '优化连接超时策略', '考虑连接复用'],
        metrics: { activeConnections: throughput.activeConnections },
        timestamp: Date.now(),
      });
    }
  }

  /**
   * 分析错误率
   */
  private analyzeErrorRate(metrics: PerformanceMetrics): void {
    const { errorRate } = metrics;
    const baseline = this.baselines.get('errorRate') ?? 1;

    if (errorRate.rate > baseline * 10) {
      this.bottlenecks.push({
        category: 'error',
        severity: 'critical',
        description: `错误率过高: ${errorRate.rate.toFixed(1)}%`,
        impact: '系统稳定性严重受损，需要立即处理',
        recommendations: [
          '立即检查错误日志',
          '识别高频错误原因',
          '实施降级和熔断策略',
          '加强监控和告警',
        ],
        metrics: { errorRate: errorRate.rate, baseline, totalErrors: errorRate.total },
        timestamp: Date.now(),
      });
    } else if (errorRate.rate > baseline * 5) {
      this.bottlenecks.push({
        category: 'error',
        severity: 'high',
        description: `错误率偏高: ${errorRate.rate.toFixed(1)}%`,
        impact: '系统稳定性受到影响',
        recommendations: ['分析错误类型和模式', '修复高频错误', '改善错误处理机制'],
        metrics: { errorRate: errorRate.rate, baseline },
        timestamp: Date.now(),
      });
    } else if (errorRate.rate > baseline * 2) {
      this.bottlenecks.push({
        category: 'error',
        severity: 'medium',
        description: `错误率轻微上升: ${errorRate.rate.toFixed(1)}%`,
        impact: '需要关注错误趋势',
        recommendations: ['监控错误率变化', '预防性问题排查', '优化错误处理逻辑'],
        metrics: { errorRate: errorRate.rate, baseline },
        timestamp: Date.now(),
      });
    }

    // 分析错误类型
    const errorTypes = Object.entries(errorRate.errorsByType);
    if (errorTypes.length > 0) {
      const [topErrorType, topErrorCount] = errorTypes.sort((a, b) => b[1] - a[1])[0];

      if (topErrorCount > errorRate.total * 0.5) {
        this.bottlenecks.push({
          category: 'error',
          severity: 'high',
          description: `特定错误类型过多: ${topErrorType} (${topErrorCount}次)`,
          impact: '存在系统性问题，需要针对性解决',
          recommendations: [
            `重点解决${topErrorType}错误`,
            '检查相关模块和依赖',
            '实施针对性修复方案',
          ],
          metrics: { count: topErrorCount },
          timestamp: Date.now(),
        });
      }
    }
  }

  /**
   * 分析资源使用
   */
  private analyzeResourceUsage(metrics: PerformanceMetrics): void {
    const { resources } = metrics;
    const cpuBaseline = this.baselines.get('cpuUsage') ?? 70;
    const memBaseline = this.baselines.get('memoryUsage') ?? 80;

    // CPU使用率分析
    if (resources.cpuUsage > 90) {
      this.bottlenecks.push({
        category: 'resource',
        severity: 'critical',
        description: `CPU使用率过高: ${resources.cpuUsage.toFixed(1)}%`,
        impact: '系统响应变慢，可能出现处理瓶颈',
        recommendations: [
          '优化CPU密集型操作',
          '增加计算资源',
          '优化算法和循环逻辑',
          '考虑异步处理',
        ],
        metrics: { cpuUsage: resources.cpuUsage, baseline: cpuBaseline },
        timestamp: Date.now(),
      });
    } else if (resources.cpuUsage > 80) {
      this.bottlenecks.push({
        category: 'resource',
        severity: 'high',
        description: `CPU使用率偏高: ${resources.cpuUsage.toFixed(1)}%`,
        impact: '需要关注CPU使用情况',
        recommendations: ['监控CPU使用趋势', '优化计算密集型任务', '考虑负载均衡'],
        metrics: { cpuUsage: resources.cpuUsage, baseline: cpuBaseline },
        timestamp: Date.now(),
      });
    }

    // 内存使用率分析
    if (resources.memoryUsage > 90) {
      this.bottlenecks.push({
        category: 'resource',
        severity: 'critical',
        description: `内存使用率过高: ${resources.memoryUsage.toFixed(1)}%`,
        impact: '可能导致OOM和系统崩溃',
        recommendations: ['检查内存泄漏', '优化数据结构和算法', '增加内存配额', '实施内存监控'],
        metrics: { memoryUsage: resources.memoryUsage, baseline: memBaseline },
        timestamp: Date.now(),
      });
    } else if (resources.memoryUsage > 85) {
      this.bottlenecks.push({
        category: 'resource',
        severity: 'high',
        description: `内存使用率偏高: ${resources.memoryUsage.toFixed(1)}%`,
        impact: '需要关注内存使用情况',
        recommendations: ['分析内存使用模式', '优化内存管理', '预防内存泄漏'],
        metrics: { memoryUsage: resources.memoryUsage, baseline: memBaseline },
        timestamp: Date.now(),
      });
    }

    // 磁盘IO分析
    if (resources.diskIO > 80) {
      this.bottlenecks.push({
        category: 'resource',
        severity: 'medium',
        description: `磁盘IO使用率过高: ${resources.diskIO.toFixed(1)}%`,
        impact: '可能影响数据库和文件操作性能',
        recommendations: ['优化磁盘访问模式', '考虑SSD升级', '实施数据库优化'],
        metrics: { diskIO: resources.diskIO },
        timestamp: Date.now(),
      });
    }

    // 网络IO分析
    if (resources.networkIO > 80) {
      this.bottlenecks.push({
        category: 'resource',
        severity: 'medium',
        description: `网络IO使用率过高: ${resources.networkIO.toFixed(1)}%`,
        impact: '可能影响网络通信性能',
        recommendations: ['优化网络传输协议', '启用数据压缩', '考虑CDN加速'],
        metrics: { networkIO: resources.networkIO },
        timestamp: Date.now(),
      });
    }
  }

  /**
   * 分析缓存性能
   */
  private analyzeCachePerformance(metrics: PerformanceMetrics): void {
    const { cache } = metrics;
    const baseline = this.baselines.get('cacheHitRate') ?? 90;

    if (cache.hitRate < baseline * 0.5) {
      this.bottlenecks.push({
        category: 'cache',
        severity: 'high',
        description: `缓存命中率过低: ${cache.hitRate.toFixed(1)}%`,
        impact: '增加数据库负载，影响响应速度',
        recommendations: [
          '优化缓存策略和键设计',
          '增加缓存容量',
          '优化缓存失效策略',
          '分析缓存访问模式',
        ],
        metrics: { cacheHitRate: cache.hitRate, baseline, cacheSize: cache.size },
        timestamp: Date.now(),
      });
    } else if (cache.hitRate < baseline * 0.8) {
      this.bottlenecks.push({
        category: 'cache',
        severity: 'medium',
        description: `缓存命中率偏低: ${cache.hitRate.toFixed(1)}%`,
        impact: '有优化空间',
        recommendations: ['调整缓存策略', '优化缓存预热', '分析缓存失效原因'],
        metrics: { cacheHitRate: cache.hitRate, baseline },
        timestamp: Date.now(),
      });
    }
  }

  /**
   * 分析数据库性能
   */
  private analyzeDatabasePerformance(metrics: PerformanceMetrics): void {
    const { database } = metrics;

    // 连接池分析
    const poolUtilization = (database.connectionPool.active / database.connectionPool.total) * 100;
    if (poolUtilization > 90) {
      this.bottlenecks.push({
        category: 'database',
        severity: 'high',
        description: `数据库连接池使用率过高: ${poolUtilization.toFixed(1)}%`,
        impact: '可能导致数据库连接等待',
        recommendations: ['增加连接池大小', '优化查询执行时间', '检查慢查询', '实施连接池监控'],
        metrics: {
          poolUtilization,
          activeConnections: database.connectionPool.active,
          totalConnections: database.connectionPool.total,
        },
        timestamp: Date.now(),
      });
    }

    // 查询时间分析
    if (database.queryTime.avg > 1000) {
      this.bottlenecks.push({
        category: 'database',
        severity: 'high',
        description: `平均查询时间过长: ${database.queryTime.avg.toFixed(1)}ms`,
        impact: '影响整体响应速度',
        recommendations: ['优化慢查询', '添加合适的索引', '优化数据库表结构', '考虑读写分离'],
        metrics: { avgQueryTime: database.queryTime.avg, slowQueries: database.queryTime.slow },
        timestamp: Date.now(),
      });
    }

    // 慢查询分析
    if (database.queryTime.slow > 10) {
      this.bottlenecks.push({
        category: 'database',
        severity: 'medium',
        description: `慢查询数量过多: ${database.queryTime.slow}`,
        impact: '影响数据库性能',
        recommendations: ['分析慢查询日志', '优化查询执行计划', '重建索引', '考虑数据库优化'],
        metrics: { slowQueries: database.queryTime.slow },
        timestamp: Date.now(),
      });
    }
  }

  /**
   * 获取性能趋势
   */
  getTrends(timeframe: '1h' | '6h' | '24h' | '7d' = '1h'): PerformanceTrend[] {
    const now = Date.now();
    const timeframes = {
      '1h': 60 * 60 * 1000,
      '6h': 6 * 60 * 60 * 1000,
      '24h': 24 * 60 * 60 * 1000,
      '7d': 7 * 24 * 60 * 60 * 1000,
    };

    const cutoff = now - timeframes[timeframe];
    const recentMetrics = this.metricsHistory.filter(m => m.timestamp >= cutoff);

    if (recentMetrics.length < 2) {
      return [];
    }

    const trends: PerformanceTrend[] = [];
    const metrics = [
      'avgResponseTime',
      'requestsPerSecond',
      'errorRate',
      'cpuUsage',
      'memoryUsage',
    ];

    metrics.forEach(metric => {
      const dataPoints = recentMetrics.map(m => ({
        timestamp: m.timestamp,
        value: this.extractMetricValue(m, metric),
      }));

      const trend = this.calculateTrend(dataPoints);
      if (trend) {
        trends.push({
          metric,
          timeframe,
          trend: trend.trend,
          changePercent: trend.changePercent,
          dataPoints,
        });
      }
    });

    return trends;
  }

  /**
   * 提取指标值
   */
  private extractMetricValue(metrics: PerformanceMetrics, metric: string): number {
    switch (metric) {
      case 'avgResponseTime':
        return metrics.responseTime.avg;
      case 'requestsPerSecond':
        return metrics.throughput.requestsPerSecond;
      case 'errorRate':
        return metrics.errorRate.rate;
      case 'cpuUsage':
        return metrics.resources.cpuUsage;
      case 'memoryUsage':
        return metrics.resources.memoryUsage;
      default:
        return 0;
    }
  }

  /**
   * 计算趋势
   */
  private calculateTrend(dataPoints: Array<{ timestamp: number; value: number }>): {
    trend: 'improving' | 'degrading' | 'stable';
    changePercent: number;
  } | null {
    if (dataPoints.length < 2) {
      return null;
    }

    const firstValue = dataPoints[0].value;
    const lastValue = dataPoints[dataPoints.length - 1].value;
    const changePercent = ((lastValue - firstValue) / firstValue) * 100;

    let trend: 'improving' | 'degrading' | 'stable';
    if (Math.abs(changePercent) < 5) {
      trend = 'stable';
    } else if (changePercent > 0) {
      // 对于响应时间和错误率，增加是坏事；对于吞吐量，增加是好事
      trend = 'degrading';
    } else {
      trend = 'improving';
    }

    return { trend, changePercent };
  }

  /**
   * 获取当前瓶颈
   */
  getBottlenecks(): PerformanceBottleneck[] {
    return this.bottlenecks.sort((a, b) => {
      const severityOrder = { critical: 4, high: 3, medium: 2, low: 1 };
      return severityOrder[b.severity] - severityOrder[a.severity];
    });
  }

  /**
   * 获取性能建议
   */
  getRecommendations(): Array<{
    priority: 'high' | 'medium' | 'low';
    category: string;
    recommendation: string;
    expectedImpact: string;
    effort: 'low' | 'medium' | 'high';
  }> {
    const recommendations: Array<{
      priority: 'high' | 'medium' | 'low';
      category: string;
      recommendation: string;
      expectedImpact: string;
      effort: 'low' | 'medium' | 'high';
    }> = [];

    // 基于瓶颈生成建议
    this.bottlenecks.forEach(bottleneck => {
      bottleneck.recommendations.forEach(rec => {
        const priority =
          bottleneck.severity === 'critical'
            ? 'high'
            : bottleneck.severity === 'high'
              ? 'high'
              : bottleneck.severity === 'medium'
                ? 'medium'
                : 'low';

        recommendations.push({
          priority,
          category: bottleneck.category,
          recommendation: rec,
          expectedImpact: bottleneck.impact,
          effort: this.estimateEffort(bottleneck.category, rec),
        });
      });
    });

    // 去重并按优先级排序
    const uniqueRecommendations = recommendations.filter(
      (rec, index, arr) => arr.findIndex(r => r.recommendation === rec.recommendation) === index
    );

    return uniqueRecommendations.sort((a, b) => {
      const priorityOrder = { high: 3, medium: 2, low: 1 };
      return priorityOrder[b.priority] - priorityOrder[a.priority];
    });
  }

  /**
   * 估算实施努力
   */
  private estimateEffort(category: string, recommendation: string): 'low' | 'medium' | 'high' {
    const lowEffortKeywords = ['监控', '检查', '分析', '调整', '配置'];
    const highEffortKeywords = ['升级', '重构', '迁移', '实施', '开发'];

    const recLower = recommendation.toLowerCase();

    if (lowEffortKeywords.some(keyword => recLower.includes(keyword))) {
      return 'low';
    }
    if (highEffortKeywords.some(keyword => recLower.includes(keyword))) {
      return 'high';
    }
    return 'medium';
  }

  /**
   * 生成性能报告
   */
  generateReport(): {
    timestamp: number;
    summary: {
      bottlenecks: {
        critical: number;
        high: number;
        medium: number;
        low: number;
      };
      trends: {
        improving: number;
        degrading: number;
        stable: number;
      };
    };
    bottlenecks: PerformanceBottleneck[];
    trends: PerformanceTrend[];
    recommendations: Array<{
      priority: 'high' | 'medium' | 'low';
      category: string;
      recommendation: string;
      expectedImpact: string;
      effort: 'low' | 'medium' | 'high';
    }>;
  } {
    const bottlenecks = this.getBottlenecks();
    const trends = this.getTrends();
    const recommendations = this.getRecommendations();

    const summary = {
      bottlenecks: {
        critical: bottlenecks.filter(b => b.severity === 'critical').length,
        high: bottlenecks.filter(b => b.severity === 'high').length,
        medium: bottlenecks.filter(b => b.severity === 'medium').length,
        low: bottlenecks.filter(b => b.severity === 'low').length,
      },
      trends: {
        improving: trends.filter(t => t.trend === 'improving').length,
        degrading: trends.filter(t => t.trend === 'degrading').length,
        stable: trends.filter(t => t.trend === 'stable').length,
      },
    };

    return {
      timestamp: Date.now(),
      summary,
      bottlenecks,
      trends,
      recommendations,
    };
  }

  /**
   * 清理历史数据
   */
  clearHistory(): void {
    this.metricsHistory = [];
    this.bottlenecks = [];
  }

  /**
   * 获取当前性能指标
   */
  getCurrentMetrics(): PerformanceMetrics | null {
    return this.metricsHistory.length > 0
      ? this.metricsHistory[this.metricsHistory.length - 1]
      : null;
  }

  /**
   * 设置性能基准
   */
  setBaseline(metric: string, value: number): void {
    this.baselines.set(metric, value);
  }

  /**
   * 获取性能基准
   */
  getBaseline(metric: string): number | undefined {
    return this.baselines.get(metric);
  }
}
