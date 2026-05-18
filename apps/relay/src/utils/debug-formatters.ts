/**
 * 调试日志格式化器
 *
 * 提供彩色输出、详细调试信息等功能
 */

import type { LogEntry, LogLevel } from '../types';

const normalizeLevel = (level: LogLevel): string =>
  typeof level === 'string' ? level.toLowerCase() : `${level}`.toLowerCase();

/**
 * 彩色控制台格式化器
 */
export class ColorConsoleFormatter {
  private static colors = {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    dim: '\x1b[2m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    magenta: '\x1b[35m',
    cyan: '\x1b[36m',
    white: '\x1b[37m',
    gray: '\x1b[90m',
  };

  /**
   * 获取日志级别颜色
   */
  private static getLevelColor(level: LogLevel): string {
    switch (normalizeLevel(level)) {
      case 'debug':
      case 'trace':
        return this.colors.gray;
      case 'warn':
      case 'warning':
        return this.colors.yellow;
      case 'error':
        return this.colors.red;
      case 'success':
      case 'info':
      default:
        return this.colors.green;
    }
  }

  /**
   * 获取标签颜色
   */
  private static getTagColor(tag: string): string {
    const tagColors: Record<string, string> = {
      request: this.colors.blue,
      websocket: this.colors.cyan,
      security: this.colors.magenta,
      error: this.colors.red,
      warning: this.colors.yellow,
      success: this.colors.green,
      debug: this.colors.gray,
      info: this.colors.green,
      performance: this.colors.yellow,
    };

    return tagColors[tag.toLowerCase()] ?? this.colors.white;
  }

  /**
   * 格式化时间戳
   */
  private static formatTimestamp(timestamp: number): string {
    const date = new Date(timestamp);
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const seconds = date.getSeconds().toString().padStart(2, '0');
    const milliseconds = date.getMilliseconds().toString().padStart(3, '0');

    return `${hours}:${minutes}:${seconds}.${milliseconds}`;
  }

  /**
   * 格式化上下文信息
   */
  private static formatContext(context: Record<string, unknown>): string {
    if (!context || Object.keys(context).length === 0) {
      return '';
    }

    try {
      const formatted = JSON.stringify(context, null, 2);
      return formatted
        .split('\n')
        .map(line => `    ${line}`)
        .join('\n');
    } catch (error) {
      return `    [Context formatting error: ${error instanceof Error ? error.message : 'Unknown'}]`;
    }
  }

  /**
   * 格式化标签
   */
  private static formatTags(tags: string[]): string {
    if (!tags || tags.length === 0) {
      return '';
    }

    return tags
      .map(tag => {
        const color = this.getTagColor(tag);
        return `${color}[${tag}]${this.colors.reset}`;
      })
      .join(' ');
  }

  /**
   * 格式化错误信息
   */
  private static formatError(error?: Error): string {
    if (!error) {
      return '';
    }

    let errorStr = `${this.colors.red}${this.colors.bright}Error: ${error.name}${this.colors.reset}\n`;
    errorStr += `${this.colors.red}Message: ${error.message}${this.colors.reset}\n`;

    if (error.stack) {
      const stackLines = error.stack.split('\n').slice(1, 6); // 只显示前5行
      errorStr += `${this.colors.red}Stack:\n${this.colors.dim}${stackLines.join('\n')}${this.colors.reset}`;
    }

    return errorStr;
  }

  /**
   * 格式化单个日志条目
   */
  public static format(entry: LogEntry): string {
    const timestamp = this.formatTimestamp(entry.timestamp);
    const levelColor = this.getLevelColor(entry.level);
    const tags = this.formatTags(entry.tags ?? []);
    const requestId = entry.requestId
      ? `${this.colors.cyan}[${entry.requestId}]${this.colors.reset}`
      : '';
    const deviceId = entry.deviceId
      ? `${this.colors.magenta}[${entry.deviceId}]${this.colors.reset}`
      : '';
    const levelLabel = normalizeLevel(entry.level).toUpperCase();

    // 构建基础日志行
    let logLine = `${this.colors.dim}[${timestamp}]${this.colors.reset} `;
    logLine += `${levelColor}${levelLabel}${this.colors.reset} `;

    if (requestId) {
      logLine += `${requestId} `;
    }
    if (deviceId) {
      logLine += `${deviceId} `;
    }
    if (tags) {
      logLine += `${tags} `;
    }

    logLine += `${this.colors.white}${entry.message}${this.colors.reset}`;

    // 添加上下文信息
    const contextStr = this.formatContext(entry.context ?? {});
    if (contextStr) {
      logLine += `\n${this.colors.dim}Context:${this.colors.reset}\n${contextStr}`;
    }

    // 添加错误信息
    const errorStr = this.formatError(entry.error);
    if (errorStr) {
      logLine += `\n${errorStr}`;
    }

    return logLine;
  }
}

/**
 * 调试模式格式化器
 */
export class DebugFormatter {
  /**
   * 格式化请求信息
   */
  public static formatRequest(entry: LogEntry): string {
    const timestamp = new Date(entry.timestamp).toISOString();
    const method = entry.context?.method ?? 'UNKNOWN';
    const url = entry.context?.url ?? '';
    const duration = entry.context?.duration ?? 0;

    let output = `\n${'='.repeat(80)}\n`;
    output += `[请求] ${timestamp} | ${method} ${url}\n`;
    output += `${'-'.repeat(80)}\n`;
    output += `Request ID: ${entry.requestId}\n`;
    output += `Duration: ${duration}ms\n`;

    if (entry.context?.ip) {
      output += `Client IP: ${entry.context.ip}\n`;
    }

    if (entry.context?.userAgent) {
      output += `User-Agent: ${entry.context.userAgent}\n`;
    }

    return output;
  }

  /**
   * 格式化响应信息
   */
  public static formatResponse(entry: LogEntry): string {
    const status = (entry.context?.status as number | undefined) ?? 0;
    const statusColor = status >= 400 ? '\x1b[31m' : status >= 300 ? '\x1b[33m' : '\x1b[32m';
    const resetColor = '\x1b[0m';

    let output = `Status: ${statusColor}${status}${resetColor}\n`;

    if (entry.context?.responseSize) {
      output += `Response Size: ${entry.context.responseSize} bytes\n`;
    }

    if (entry.context?.contentType) {
      output += `Content-Type: ${entry.context.contentType}\n`;
    }

    output += `${'='.repeat(80)}\n`;

    return output;
  }

  /**
   * 格式化WebSocket事件
   */
  public static formatWebSocketEvent(entry: LogEntry): string {
    const timestamp = new Date(entry.timestamp).toISOString();
    const event = entry.context?.event ?? 'unknown';
    const deviceId = entry.deviceId ?? 'unknown';

    let output = `\n[WebSocket] ${timestamp} | WebSocket Event\n`;
    output += `${'-'.repeat(50)}\n`;
    output += `Device: ${deviceId}\n`;
    output += `Event: ${event}\n`;

    if (entry.context?.messageType) {
      output += `Message Type: ${entry.context.messageType}\n`;
    }

    if (entry.context?.connectionId) {
      output += `Connection ID: ${entry.context.connectionId}\n`;
    }

    output += `${'='.repeat(50)}\n`;

    return output;
  }

  /**
   * 格式化性能数据
   */
  public static formatPerformance(entry: LogEntry): string {
    const timestamp = new Date(entry.timestamp).toISOString();
    const operation = entry.context?.operation ?? 'unknown';
    const duration = (entry.context?.duration as number | undefined) ?? 0;
    const memory = (entry.context?.memory as number | undefined) ?? 0;

    let output = `[性能] ${timestamp} | Performance\n`;
    output += `${'-'.repeat(40)}\n`;
    output += `Operation: ${operation}\n`;
    output += `Duration: ${duration}ms\n`;

    if (memory > 0) {
      output += `Memory: ${(memory / 1024 / 1024).toFixed(2)}MB\n`;
    }

    if (entry.context?.cpuUsage) {
      output += `CPU: ${entry.context.cpuUsage}%\n`;
    }

    return output;
  }

  /**
   * 格式化安全事件
   */
  public static formatSecurityEvent(entry: LogEntry): string {
    const timestamp = new Date(entry.timestamp).toISOString();
    const threatType = entry.context?.threatType ?? 'unknown';
    const severity = entry.context?.severity ?? 'medium';
    const ip = entry.context?.ip ?? 'unknown';

    let output = `[安全] ${timestamp} | Security Event\n`;
    output += `${'-'.repeat(50)}\n`;
    output += `Threat Type: ${threatType}\n`;
    output += `Severity: ${severity}\n`;
    output += `Source IP: ${ip}\n`;

    if (entry.context?.blocked) {
      output += 'Action: BLOCKED [阻止]\n';
    } else {
      output += 'Action: MONITORED [监控]\n';
    }

    output += `${'='.repeat(50)}\n`;

    return output;
  }
}

/**
 * 调试日志记录器
 */
export class DebugLogger {
  private static isDebugMode(): boolean {
    // 在 Cloudflare Workers 中，我们假设调试模式总是启用
    // 因为只有在调试配置中才会加载这些工具
    return true;
  }

  /**
   * 记录详细请求信息
   */
  public static logRequest(entry: LogEntry): void {
    if (!this.isDebugMode()) {
      return;
    }

    console.log(DebugFormatter.formatRequest(entry));
  }

  /**
   * 记录详细响应信息
   */
  public static logResponse(entry: LogEntry): void {
    if (!this.isDebugMode()) {
      return;
    }

    console.log(DebugFormatter.formatResponse(entry));
  }

  /**
   * 记录WebSocket事件
   */
  public static logWebSocketEvent(entry: LogEntry): void {
    if (!this.isDebugMode()) {
      return;
    }

    console.log(DebugFormatter.formatWebSocketEvent(entry));
  }

  /**
   * 记录性能数据
   */
  public static logPerformance(entry: LogEntry): void {
    if (!this.isDebugMode()) {
      return;
    }

    console.log(DebugFormatter.formatPerformance(entry));
  }

  /**
   * 记录安全事件
   */
  public static logSecurityEvent(entry: LogEntry): void {
    if (!this.isDebugMode()) {
      return;
    }

    console.log(DebugFormatter.formatSecurityEvent(entry));
  }

  /**
   * 记录分隔线
   */
  public static logSeparator(title?: string): void {
    if (!this.isDebugMode()) {
      return;
    }

    if (title) {
      console.log(`\n${'='.repeat(80)}`);
      console.log(`  ${title}`);
      console.log(`${'='.repeat(80)}\n`);
    } else {
      console.log(`${'-'.repeat(80)}`);
    }
  }

  /**
   * 记录表格数据
   */
  public static logTable(data: Record<string, unknown>, title?: string): void {
    if (!this.isDebugMode()) {
      return;
    }

    if (title) {
      console.log(`\n[表格] ${title}\n`);
    }

    console.table(data);
  }

  /**
   * 记录调试信息（带颜色）
   */
  public static logDebug(message: string, data?: unknown): void {
    if (!this.isDebugMode()) {
      return;
    }

    console.log(`\x1b[36m[调试] DEBUG:\x1b[0m ${message}`);
    if (data) {
      console.log(data);
    }
  }

  /**
   * 记录成功信息（带颜色）
   */
  public static logSuccess(message: string, data?: unknown): void {
    if (!this.isDebugMode()) {
      return;
    }

    console.log(`\x1b[32m[成功] SUCCESS:\x1b[0m ${message}`);
    if (data) {
      console.log(data);
    }
  }

  /**
   * 记录警告信息（带颜色）
   */
  public static logWarning(message: string, data?: unknown): void {
    if (!this.isDebugMode()) {
      return;
    }

    console.log(`\x1b[33m[警告] WARNING:\x1b[0m ${message}`);
    if (data) {
      console.log(data);
    }
  }

  /**
   * 记录错误信息（带颜色）
   */
  public static logError(message: string, error?: Error | unknown): void {
    if (!this.isDebugMode()) {
      return;
    }

    console.log(`\x1b[31m[错误] ERROR:\x1b[0m ${message}`);
    if (error) {
      if (error instanceof Error) {
        console.log(error.stack);
      } else {
        console.log(error);
      }
    }
  }
}
