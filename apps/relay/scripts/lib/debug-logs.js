#!/usr/bin/env node

/**
 * CicadaRelay 日志调试工具
 *
 * 提供日志查看、过滤、分析等功能
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
    white: '\x1b[37m'
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
 * Wrangler日志监控器
 */
class LogMonitor {
  constructor() {
    this.isRunning = false;
    this.logs = [];
    this.filters = {
      level: [],
      requestId: [],
      deviceId: [],
      tag: []
    };
    this.stats = {
      total: 0,
      byLevel: {},
      byTag: {},
      byHour: {}
    };
  }

  /**
   * 启动日志监控
   */
  start() {
    if (this.isRunning) {
      colorLog('[警告] 日志监控已在运行中', 'yellow');
      return;
    }

    colorLog('\n[监控] 启动CicadaRelay日志监控', 'cyan');
    colorLog('=' .repeat(50), 'cyan');

    // 使用wrangler tail命令获取实时日志
    const wrangler = spawn('wrangler', ['tail', '--format', 'json'], {
      stdio: 'inherit',
      stderr: 'inherit'
    });

    wrangler.stdout.on('data', (data) => {
      this.processLogData(data.toString());
    });

    wrangler.stderr.on('data', (data) => {
      const errorOutput = data.toString();
      if (errorOutput.includes('error')) {
        colorLog(`[错误] Wrangler错误: ${errorOutput}`, 'red');
      }
    });

    wrangler.on('close', (code) => {
      this.isRunning = false;
      colorLog(`\n[统计] 日志监控已停止 (退出码: ${code})`, 'yellow');
      this.printStats();
    });

    wrangler.on('error', (error) => {
      colorLog(`[崩溃] 无法启动wrangler tail: ${error.message}`, 'red');
      process.exit(1);
    });

    this.isRunning = true;
    colorLog('[成功] 日志监控已启动', 'green');
    colorLog('[日志] 日志将实时显示，按 Ctrl+C 停止', 'blue');
    colorLog('⚙️  支持的过滤命令将在未来版本中添加', 'gray');
  }

  /**
   * 处理日志数据
   */
  processLogData(data) {
    try {
      const lines = data.toString().trim().split('\n');

      for (const line of lines) {
        if (line.trim()) {
          this.parseAndDisplayLog(line);
        }
      }
    } catch (error) {
      colorLog(`[错误] 日志解析错误: ${error.message}`, 'red');
    }
  }

  /**
   * 解析并显示日志
   */
  parseAndDisplayLog(logLine) {
    try {
      // 尝试解析JSON格式的日志
      const logEntry = JSON.parse(logLine);
      this.displayLogEntry(logEntry);
      this.updateStats(logEntry);
    } catch (error) {
      // 如果不是JSON，可能是其他格式的日志
      this.displayRawLog(logLine);
    }
  }

  /**
   * 显示结构化日志条目
   */
  displayLogEntry(logEntry) {
    const timestamp = new Date(logEntry.timestamp || Date.now()).toLocaleTimeString();
    const level = logEntry.level || 'INFO';
    const message = logEntry.message || '';
    const requestId = logEntry.requestId || '';
    const deviceId = logEntry.deviceId || '';
    const tags = logEntry.tags || [];

    // 检查过滤器
    if (!this.shouldDisplay(logEntry)) {
      return;
    }

    // 格式化输出
    let output = `[${timestamp}]`;

    // 添加级别颜色
    const levelColors = {
      DEBUG: CONFIG.COLORS.gray,
      INFO: CONFIG.COLORS.green,
      WARN: CONFIG.COLORS.yellow,
      ERROR: CONFIG.COLORS.red
    };

    output += ` ${levelColors[level]}${level}${CONFIG.COLORS.reset}`;

    // 添加请求ID
    if (requestId) {
      output += ` ${CONFIG.COLORS.cyan}[${requestId}]${CONFIG.COLORS.reset}`;
    }

    // 添加设备ID
    if (deviceId) {
      output += ` ${CONFIG.COLORS.magenta}[${deviceId}]${CONFIG.COLORS.reset}`;
    }

    // 添加标签
    if (tags.length > 0) {
      const tagColors = {
        request: CONFIG.COLORS.blue,
        websocket: CONFIG.COLORS.cyan,
        security: CONFIG.COLORS.magenta,
        error: CONFIG.COLORS.red,
        performance: CONFIG.COLORS.yellow
      };

      const tagOutput = tags.map(tag => {
        const color = tagColors[tag.toLowerCase()] || CONFIG.COLORS.white;
        return `${color}[${tag}]${CONFIG.COLORS.reset}`;
      }).join(' ');
      output += ` ${tagOutput}`;
    }

    // 添加消息
    output += ` ${message}`;

    console.log(output);

    // 显示上下文信息（如果有）
    if (logEntry.context && Object.keys(logEntry.context).length > 0) {
      console.log(`${CONFIG.COLORS.dim}  Context: ${JSON.stringify(logEntry.context, null, 2)}${CONFIG.COLORS.reset}`);
    }

    // 显示错误信息（如果有）
    if (logEntry.error) {
      console.log(`${CONFIG.COLORS.red}  Error: ${logEntry.error.message}${CONFIG.COLORS.reset}`);
      if (logEntry.error.stack) {
        console.log(`${CONFIG.COLORS.dim}  Stack: ${logEntry.error.stack}${CONFIG.COLORS.reset}`);
      }
    }
  }

  /**
   * 显示原始日志
   */
  displayRawLog(logLine) {
    // 检查是否包含错误信息
    if (logLine.toLowerCase().includes('error')) {
      colorLog(logLine, 'red');
    } else if (logLine.toLowerCase().includes('warn')) {
      colorLog(logLine, 'yellow');
    } else {
      console.log(logLine);
    }
  }

  /**
   * 检查是否应该显示此日志
   */
  shouldDisplay(logEntry) {
    // 级别过滤
    if (this.filters.level.length > 0 && !this.filters.level.includes(logEntry.level)) {
      return false;
    }

    // 请求ID过滤
    if (this.filters.requestId.length > 0 && logEntry.requestId &&
        !this.filters.requestId.some(id => logEntry.requestId.includes(id))) {
      return false;
    }

    // 设备ID过滤
    if (this.filters.deviceId.length > 0 && logEntry.deviceId &&
        !this.filters.deviceId.some(id => logEntry.deviceId.includes(id))) {
      return false;
    }

    // 标签过滤
    if (this.filters.tag.length > 0 && logEntry.tags &&
        !logEntry.tags.some(tag => this.filters.tag.includes(tag))) {
      return false;
    }

    return true;
  }

  /**
   * 更新统计信息
   */
  updateStats(logEntry) {
    this.stats.total++;

    // 按级别统计
    const level = logEntry.level || 'INFO';
    this.stats.byLevel[level] = (this.stats.byLevel[level] || 0) + 1;

    // 按标签统计
    if (logEntry.tags) {
      logEntry.tags.forEach(tag => {
        this.stats.byTag[tag] = (this.stats.byTag[tag] || 0) + 1;
      });
    }

    // 按小时统计
    const hour = new Date().getHours();
    this.stats.byHour[hour] = (this.stats.byHour[hour] || 0) + 1;
  }

  /**
   * 打印统计信息
   */
  printStats() {
    colorLog('\n[统计] 日志统计信息', 'cyan');
    colorLog('=' .repeat(50), 'cyan');

    colorLog(`总日志数: ${this.stats.total}`, 'blue');

    // 按级别统计
    colorLog('\n[图表] 按级别统计:', 'yellow');
    Object.entries(this.stats.byLevel).forEach(([level, count]) => {
      const percentage = ((count / this.stats.total) * 100).toFixed(1);
      colorLog(`  ${level}: ${count} (${percentage}%)`, 'white');
    });

    // 按标签统计
    if (Object.keys(this.stats.byTag).length > 0) {
      colorLog('\n[标签] 按标签统计:', 'yellow');
      Object.entries(this.stats.byTag).forEach(([tag, count]) => {
        const percentage = ((count / this.stats.total) * 100).toFixed(1);
        colorLog(`  ${tag}: ${count} (${percentage}%)`, 'white');
      });
    }

    // 按小时统计
    colorLog('\n[时间] 按小时统计:', 'yellow');
    Object.entries(this.stats.byHour).forEach(([hour, count]) => {
      const percentage = ((count / this.stats.total) * 100).toFixed(1);
      colorLog(`  ${hour.toString().padStart(2, '0')}:00 - ${count} (${percentage}%)`, 'white');
    });
  }

  /**
   * 设置过滤器
   */
  setFilter(type, value) {
    switch (type) {
      case 'level':
        this.filters.level = Array.isArray(value) ? value : [value];
        break;
      case 'requestId':
        this.filters.requestId = Array.isArray(value) ? value : [value];
        break;
      case 'deviceId':
        this.filters.deviceId = Array.isArray(value) ? value : [value];
        break;
      case 'tag':
        this.filters.tag = Array.isArray(value) ? value : [value];
        break;
    }
  }
}

/**
 * 日志分析器
 */
class LogAnalyzer {
  constructor() {
    this.patterns = {
      error: /\b(error|fail|exception|timeout)/i,
      warning: /\b(warn|warning|deprecated)/i,
      performance: /\b(duration|slow|timeout|performance)/i,
      security: /\b(security|auth|forbidden|unauthorized)/i,
      websocket: /\b(websocket|ws|connection)/i
    };
  }

  /**
   * 分析日志文件
   */
  async analyzeLogFile(filePath) {
    colorLog('\n🔬 分析日志文件', 'magenta');
    colorLog(`文件路径: ${filePath}`, 'blue');
    colorLog('=' .repeat(50), 'magenta');

    try {
      const fs = await import('fs');
      const content = fs.readFileSync(filePath, 'utf8');
      const lines = content.split('\n');

      const analysis = {
        totalLines: lines.length,
        patterns: {},
        errors: [],
        warnings: [],
        timeRange: { start: null, end: null }
      };

      let errorCount = 0;
      let warningCount = 0;

      lines.forEach((line, index) => {
        // 分析模式
        Object.entries(this.patterns).forEach(([patternName, regex]) => {
          if (regex.test(line)) {
            analysis.patterns[patternName] = (analysis.patterns[patternName] || 0) + 1;
          }
        });

        // 提取错误信息
        if (line.includes('ERROR') || line.includes('error')) {
          errorCount++;
          if (errorCount <= 10) { // 只保存前10个错误
            analysis.errors.push({
              line: index + 1,
              content: line.trim()
            });
          }
        }

        // 提取警告信息
        if (line.includes('WARN') || line.includes('warning')) {
          warningCount++;
          if (warningCount <= 5) { // 只保存前5个警告
            analysis.warnings.push({
              line: index + 1,
              content: line.trim()
            });
          }
        }
      });

      this.printAnalysis(analysis);

    } catch (error) {
      colorLog(`[错误] 分析失败: ${error.message}`, 'red');
    }
  }

  /**
   * 打印分析结果
   */
  printAnalysis(analysis) {
    colorLog('\n[统计] 日志分析结果', 'cyan');
    colorLog('=' .repeat(50), 'cyan');

    colorLog(`总行数: ${analysis.totalLines}`, 'blue');

    // 模式匹配统计
    colorLog('\n[查询] 模式匹配统计:', 'yellow');
    Object.entries(analysis.patterns).forEach(([pattern, count]) => {
      const percentage = ((count / analysis.totalLines) * 100).toFixed(2);
      colorLog(`  ${pattern}: ${count} (${percentage}%)`, 'white');
    });

    // 错误信息
    if (analysis.errors.length > 0) {
      colorLog('\n[错误] 发现的错误 (前10个):', 'red');
      analysis.errors.forEach(error => {
        colorLog(`  第${error.line}行: ${error.content}`, 'red');
      });
    }

    // 警告信息
    if (analysis.warnings.length > 0) {
      colorLog('\n[警告]  发现的警告 (前5个):', 'yellow');
      analysis.warnings.forEach(warning => {
        colorLog(`  第${warning.line}行: ${warning.content}`, 'yellow');
      });
    }
  }
}

/**
 * 命令行接口
 */
async function main() {
  const args = process.argv.slice(2);
  const monitor = new LogMonitor();
  const analyzer = new LogAnalyzer();

  if (args.length === 0) {
    // 显示帮助信息
    colorLog('\n[工具] CicadaRelay日志调试工具', 'bright');
    colorLog('=' .repeat(50), 'bright');
    colorLog('\n使用方法:', 'yellow');
    colorLog('  node debug-logs.js [命令] [参数]', 'white');
    colorLog('\n可用命令:', 'yellow');
    colorLog('  monitor             - 启动实时日志监控', 'white');
    colorLog('  analyze <file>      - 分析日志文件', 'white');
    colorLog('  filter <type> <value> - 设置过滤器 (level/requestId/deviceId/tag)', 'white');
    colorLog('  stats               - 显示当前统计信息', 'white');
    colorLog('\n示例:', 'cyan');
    colorLog('  node debug-logs.js monitor', 'white');
    colorLog('  node debug-logs.js analyze logs.txt', 'white');
    colorLog('  node debug-logs.js filter level ERROR', 'white');
    colorLog('  node debug-logs.js filter requestId req-123', 'white');

    process.exit(0);
  }

  const command = args[0];

  switch (command) {
    case 'monitor':
      monitor.start();
      break;

    case 'analyze':
      const logFile = args[1];
      if (!logFile) {
        colorLog('[错误] 请指定要分析的日志文件', 'red');
        process.exit(1);
      }
      await analyzer.analyzeLogFile(logFile);
      break;

    case 'filter':
      const filterType = args[1];
      const filterValue = args[2];
      if (!filterType || !filterValue) {
        colorLog('[错误] 请指定过滤类型和值', 'red');
        colorLog('支持的类型: level, requestId, deviceId, tag', 'yellow');
        process.exit(1);
      }
      monitor.setFilter(filterType, filterValue);
      colorLog(`[成功] 设置过滤器: ${filterType} = ${filterValue}`, 'green');
      break;

    case 'stats':
      monitor.printStats();
      break;

    default:
      colorLog(`[错误] 未知命令: ${command}`, 'red');
      colorLog('运行 "node debug-logs.js" 查看帮助', 'yellow');
      process.exit(1);
  }
}

// 运行主程序
main().catch(error => {
  colorLog(`[崩溃] 程序执行失败: ${error.message}`, 'red');
  process.exit(1);
});