import type { CommandRequest, CommandType } from '../types/command.types.js';
import type { JsonValue } from '../types/common.types.js';
import { COMMANDS } from '../protocol/commands.js';
import { BaseValidator } from './base.validator.js';

/**
 * 支持的命令集合（权威列表）
 *
 * 运行时集合从 protocol/commands.ts 的唯一列表派生。
 */
export const SUPPORTED_COMMANDS: ReadonlySet<string> = new Set(COMMANDS);

/**
 * Device ID 格式验证正则表达式
 * 统一为 MAC_[32位十六进制]
 */
export const DEVICE_ID_PATTERN = /^MAC_[A-F0-9]{32}$/i;

/**
 * 校验 deviceId 是否符合 MAC_[32位十六进制] 格式（M10 复用）
 */
export function isValidDeviceId(value: string): boolean {
  return DEVICE_ID_PATTERN.test(value);
}

/**
 * 命令请求验证器
 *
 * 职责：
 * - ✅ 验证请求格式（必填字段、字段类型）
 * - ✅ 验证命令是否在契约中（SUPPORTED_COMMANDS）
 * - ✅ 验证 device_id 格式
 * - ❌ 不验证业务逻辑（如设备状态、权限等）
 *
 * 这是 Shortcuts gateway 明文命令载荷的契约层验证器。
 * Cicada 执行层会进行额外的防御性验证。
 */
export class CommandValidator extends BaseValidator<CommandRequest> {
  /**
   * 验证命令请求
   *
   * @param payload - 命令请求对象
   * @returns 验证是否通过
   */
  validate(payload: CommandRequest): boolean {
    this.clear();

    // 验证 payload 本身
    if (!payload || typeof payload !== 'object') {
      this.addError('Request payload must be a valid object');
      return false;
    }

    // 验证必填字段
    this.validateRequiredFields(payload);

    // 验证字段类型和格式
    this.validateFieldTypes(payload);

    // 验证命令在契约中
    this.validateCommand(payload.command);

    // 验证可选参数
    if (payload.params !== undefined) {
      this.validateParams(payload.params);
    }

    return this.errors.length === 0;
  }

  /**
   * 验证必填字段是否存在
   */
  private validateRequiredFields(payload: CommandRequest): void {
    const requiredFields: Array<keyof CommandRequest> = [
      'device_id',
      'command',
    ];

    for (const field of requiredFields) {
      if (payload[field] === undefined || payload[field] === null) {
        this.addError(`Field '${field}' is required`);
      } else if (typeof payload[field] === 'string' && (payload[field] as string).trim() === '') {
        this.addError(`Field '${field}' cannot be empty`);
      }
    }
  }

  /**
   * 验证字段类型
   */
  private validateFieldTypes(payload: CommandRequest): void {
    // 验证 device_id 类型和格式
    if (payload.device_id !== undefined && payload.device_id !== null) {
      if (typeof payload.device_id !== 'string') {
        this.addError(`Field 'device_id' must be a string, got ${typeof payload.device_id}`);
      } else if (!DEVICE_ID_PATTERN.test(payload.device_id)) {
        this.addError(
          `Field 'device_id' has invalid format. Must match MAC_[32 hex]`
        );
      }
    }

    // 验证 command 类型
    if (payload.command !== undefined && payload.command !== null) {
      if (typeof payload.command !== 'string') {
        this.addError(`Field 'command' must be a string, got ${typeof payload.command}`);
      }
    }

    // 验证 request_id 类型（可选）
    if (payload.request_id !== undefined && payload.request_id !== null) {
      if (typeof payload.request_id !== 'string') {
        this.addError(`Field 'request_id' must be a string, got ${typeof payload.request_id}`);
      }
    }

    // 验证 params 类型
    if (payload.params !== undefined && payload.params !== null) {
      if (typeof payload.params !== 'object' || Array.isArray(payload.params)) {
        this.addError(`Field 'params' must be an object, got ${typeof payload.params}`);
      }
    }

  }

  /**
   * 验证命令是否在支持列表中
   */
  private validateCommand(cmd: string | undefined): void {
    if (!cmd) {
      return; // 已在 validateRequiredFields 中处理
    }

    if (!SUPPORTED_COMMANDS.has(cmd)) {
      const supportedList = Array.from(SUPPORTED_COMMANDS).join(', ');
      this.addError(
        `Unsupported command: '${cmd}'. Supported commands: ${supportedList}`
      );
    }
  }

  /**
   * 验证命令参数
   *
   * 只做基础验证：
   * - 参数值不能为 undefined
   * - 参数必须是有效的 JSON 值
   */
  private validateParams(params: Record<string, JsonValue>): void {
    if (!params || typeof params !== 'object') {
      return; // 已在 validateFieldTypes 中处理
    }

    for (const [key, value] of Object.entries(params)) {
      if (value === undefined) {
        this.addError(`Parameter '${key}' cannot be undefined`);
      }

      // 验证参数键名格式（可选，但推荐）
      if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(key)) {
        this.addError(
          `Parameter key '${key}' has invalid format. Must start with letter or underscore, ` +
          `followed by letters, numbers, or underscores`
        );
      }
    }
  }

  /**
   * 获取格式化的错误信息
   *
   * @returns 格式化的错误信息字符串，如果没有错误则返回空字符串
   */
  getFormattedErrors(): string {
    if (this.errors.length === 0) {
      return '';
    }

    if (this.errors.length === 1) {
      return this.errors[0] ?? '';
    }

    return `Validation failed with ${this.errors.length} errors:\n` +
      this.errors.map((err, idx) => `  ${idx + 1}. ${err}`).join('\n');
  }

  /**
   * 检查特定字段是否有错误
   *
   * @param field - 字段名
   * @returns 是否有该字段的错误
   */
  hasFieldError(field: string): boolean {
    return this.errors.some(err => err.toLowerCase().includes(field.toLowerCase()));
  }
}

/**
 * 快速验证命令请求的辅助函数
 *
 * @param payload - 命令请求对象
 * @returns 验证结果对象
 */
export function validateCommandRequest(payload: CommandRequest): {
  valid: boolean;
  errors: string[];
  formattedError: string;
} {
  const validator = new CommandValidator();
  const valid = validator.validate(payload);

  return {
    valid,
    errors: validator.getErrors(),
    formattedError: validator.getFormattedErrors(),
  };
}

/**
 * 检查命令是否被支持
 *
 * @param cmd - 命令字符串
 * @returns 命令是否在支持列表中
 */
export function isCommandSupported(cmd: string): cmd is CommandType {
  return SUPPORTED_COMMANDS.has(cmd);
}

/**
 * 获取所有支持的命令列表
 *
 * @returns 支持的命令数组
 */
export function getSupportedCommands(): CommandType[] {
  return [...COMMANDS];
}
