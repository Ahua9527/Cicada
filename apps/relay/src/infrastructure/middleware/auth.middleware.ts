/**
 * 认证中间件
 */

import type { Middleware } from './types';
import { validateApiKeyRequest } from '@/utils/crypto';
import { validateCommandRequest } from '@cicada/shared/validators';
import type { CommandRequest, ValidationResult } from '@/types';

/**
 * API Key 验证中间件
 */
export function authMiddleware(_allowedCommands?: string[]): Middleware {
  return async (context, next) => {
    // 只验证POST请求
    if (context.method !== 'POST') {
      return next();
    }

    try {
      const rawBody: unknown = await context.request.json();

      // 类型转换：将字符串 ts 转换为数字（兼容不同客户端实现）
      const body: CommandRequest = {
        ...(rawBody as Record<string, unknown>),
        ts:
          typeof (rawBody as Record<string, unknown>).ts === 'string'
            ? parseInt((rawBody as Record<string, unknown>).ts as string, 10)
            : ((rawBody as Record<string, unknown>).ts as number),
      } as CommandRequest;

      // 记录收到的请求体
      context.logger.info('Auth: Processing request', {
        requestId: context.requestId,
        context: {
          device_id: body.device_id,
          cmd: body.cmd,
          ts: body.ts,
          ts_type: typeof body.ts,
          has_api_key: !!body.api_key,
        },
        tags: ['auth', 'debug'],
      });

      // 使用简化的API Key验证
      const validation: ValidationResult = validateApiKeyRequest(body, context.env.API_KEY);

      if (!validation.valid) {
        context.logger.warn('Auth: Validation failed', {
          requestId: context.requestId,
          error: validation.error,
          details: validation.details,
          device_id: body.device_id,
          cmd: body.cmd,
          tags: ['auth', 'validation_failed'],
        });

        // 认证错误返回401，其他验证错误返回400
        const isAuthError =
          validation.error === 'INVALID_API_KEY' || validation.error === 'MISSING_REQUIRED_FIELDS';
        const statusCode = isAuthError ? 401 : 400;

        return {
          continue: false,
          response: Response.json(
            {
              ok: false,
              error: validation.error,
              error_code: validation.error,
              details: validation.details,
            },
            { status: statusCode }
          ),
        };
      }

      // 使用 Shared 包的 CommandValidator 进行完整验证
      const commandValidation = validateCommandRequest(body);
      if (!commandValidation.valid) {
        context.logger.warn('Auth: Command validation failed', {
          requestId: context.requestId,
          errors: commandValidation.errors,
          device_id: body.device_id,
          cmd: body.cmd,
          tags: ['auth', 'command_validation_failed'],
        });

        return {
          continue: false,
          response: Response.json(
            {
              ok: false,
              error: 'INVALID_COMMAND_REQUEST',
              error_code: 'INVALID_COMMAND_REQUEST',
              details: {
                message: commandValidation.formattedError,
                errors: commandValidation.errors,
              },
            },
            { status: 400 }
          ),
        };
      }

      // 验证通过，将解析后的请求添加到上下文
      context.validatedRequest = body;
      context.deviceId = body.device_id;

      return next();
    } catch (error) {
      context.logger.error('Auth: Request parsing failed', {
        requestId: context.requestId,
        error: error instanceof Error ? error.message : String(error),
        tags: ['auth', 'error'],
      });

      return {
        continue: false,
        response: Response.json(
          {
            ok: false,
            error: '请求格式无效',
            error_code: 'INVALID_REQUEST_FORMAT',
            details: error instanceof Error ? error.message : undefined,
          },
          { status: 400 }
        ),
      };
    }
  };
}
