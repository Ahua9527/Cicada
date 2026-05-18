import { Result } from '@cicada/shared/errors';
import { ErrorCode, ErrorSeverity, CicadaError } from '@cicada/shared/errors';
import type { JsonValue, DeviceId } from '@cicada/shared/types/common.types';
import type { CommandType, CommandParams } from '@cicada/shared/types/command.types';
import { CommandValidator as SharedCommandValidator } from '@cicada/shared/validators';
import {
  Command,
  CommandId,
  CommandTimestamp,
  CommandStatus,
  CommandPriority,
  type CommandProps,
} from './command.entity';

export type CommandValidationInput = {
  commandId?: string | null;
  deviceId: DeviceId;
  type: CommandType;
  params?: CommandParams;
  createdAt?: number;
  queuedAt?: number | null;
  executingAt?: number | null;
  completedAt?: number | null;
  status?: CommandStatus;
  priority?: CommandPriority;
  retryCount?: number;
  maxRetries?: number;
  timeoutMs?: number;
  nonce?: string;
  error?: string | null;
  result?: JsonValue;
};

export class CommandValidationError extends CicadaError {
  constructor(message: string, context?: Record<string, JsonValue>) {
    super(message, ErrorCode.VALIDATION_ERROR, { severity: ErrorSeverity.MEDIUM, context });
    this.name = 'CommandValidationError';
  }
}

export class CommandValidator {
  private readonly baseValidator = new SharedCommandValidator();

  validate(input: CommandValidationInput): Result<Command, CommandValidationError> {
    if (!input.deviceId || input.deviceId.trim() === '') {
      return Result.err(
        new CommandValidationError('Device ID cannot be empty', { deviceId: input.deviceId })
      );
    }

    if (input.commandId != null) {
      const commandId = CommandId.create(input.commandId);
      if (!commandId) {
        return Result.err(
          new CommandValidationError('Command ID must match CMD_[32 hex] format', {
            commandId: input.commandId,
          })
        );
      }
    }

    const createdAt = CommandTimestamp.create(input.createdAt) ?? CommandTimestamp.now();
    const queuedAt = CommandTimestamp.create(input.queuedAt ?? null);
    const executingAt = CommandTimestamp.create(input.executingAt ?? null);
    const completedAt = CommandTimestamp.create(input.completedAt ?? null);

    if (queuedAt && queuedAt.toNumber() < createdAt.toNumber()) {
      return Result.err(
        new CommandValidationError('queuedAt cannot be before createdAt', {
          createdAt: createdAt.toNumber(),
          queuedAt: queuedAt.toNumber(),
        })
      );
    }

    if (executingAt && queuedAt && executingAt.toNumber() < queuedAt.toNumber()) {
      return Result.err(
        new CommandValidationError('executingAt cannot be before queuedAt', {
          queuedAt: queuedAt.toNumber(),
          executingAt: executingAt.toNumber(),
        })
      );
    }

    if (completedAt && executingAt && completedAt.toNumber() < executingAt.toNumber()) {
      return Result.err(
        new CommandValidationError('completedAt cannot be before executingAt', {
          executingAt: executingAt.toNumber(),
          completedAt: completedAt.toNumber(),
        })
      );
    }

    if (input.maxRetries != null && input.maxRetries < 0) {
      return Result.err(
        new CommandValidationError('maxRetries cannot be negative', {
          maxRetries: input.maxRetries,
        })
      );
    }

    if (input.retryCount != null && input.retryCount < 0) {
      return Result.err(
        new CommandValidationError('retryCount cannot be negative', {
          retryCount: input.retryCount,
        })
      );
    }

    if (input.timeoutMs != null && input.timeoutMs <= 0) {
      return Result.err(
        new CommandValidationError('timeoutMs must be positive', { timeoutMs: input.timeoutMs })
      );
    }

    const props: CommandProps = {
      commandId: input.commandId ? (CommandId.create(input.commandId) ?? undefined) : undefined,
      deviceId: input.deviceId,
      type: input.type,
      params: input.params,
      createdAt: createdAt.toNumber(),
      queuedAt: queuedAt?.toNumber() ?? null,
      executingAt: executingAt?.toNumber() ?? null,
      completedAt: completedAt?.toNumber() ?? null,
      status: input.status,
      priority: input.priority,
      retryCount: input.retryCount,
      maxRetries: input.maxRetries,
      timeoutMs: input.timeoutMs,
      nonce: input.nonce,
      error: input.error,
      result: input.result,
    };

    return Result.ok(Command.create(props)) as Result<Command, CommandValidationError>;
  }
}
