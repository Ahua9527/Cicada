import type { Result } from '@cicada/shared/errors/result';
import { CicadaError, ErrorCode, ErrorSeverity } from '@cicada/shared/errors';
import type { DeviceId } from '@cicada/shared/types/common.types';
import type { CommandType, CommandParams } from '@cicada/shared/types/command.types';
import { Command, CommandId, CommandPriority } from '../../domain/command/command.entity';
import { requireJsonValue } from '../../utils/json-value';

export interface CommandQueue {
  enqueue(command: Command): Promise<Result<void, CicadaError>>;
  dequeue(deviceId: DeviceId): Promise<Result<Command | null, CicadaError>>;
  find(commandId: CommandId): Promise<Result<Command | null, CicadaError>>;
  listPending(deviceId: DeviceId): Promise<Result<Command[], CicadaError>>;
}

export interface CommandServiceDeps {
  commandQueue: CommandQueue;
}

export class CommandService {
  constructor(private readonly deps: CommandServiceDeps) {}

  async createCommand(
    deviceId: DeviceId,
    type: CommandType,
    params?: CommandParams,
    options?: {
      priority?: CommandPriority;
      maxRetries?: number;
      timeoutMs?: number;
    }
  ): Promise<Result<Command, CicadaError>> {
    try {
      const command = Command.create({
        deviceId,
        type,
        params,
        priority: options?.priority,
        maxRetries: options?.maxRetries,
        timeoutMs: options?.timeoutMs,
      });

      const enqueueResult = await this.deps.commandQueue.enqueue(command);
      if (!enqueueResult.success) {
        return { success: false, error: enqueueResult.error };
      }

      command.markQueued();

      return { success: true, data: command };
    } catch (error) {
      return {
        success: false,
        error: new CicadaError('Failed to create command', ErrorCode.SYSTEM_ERROR, {
          severity: ErrorSeverity.HIGH,
          cause: error instanceof Error ? error : undefined,
        }),
      };
    }
  }

  async getCommand(commandId: CommandId): Promise<Result<Command | null, CicadaError>> {
    return this.deps.commandQueue.find(commandId);
  }

  async getNextCommand(deviceId: DeviceId): Promise<Result<Command | null, CicadaError>> {
    const dequeueResult = await this.deps.commandQueue.dequeue(deviceId);
    if (!dequeueResult.success) {
      return dequeueResult;
    }

    const command = dequeueResult.data;
    if (command) {
      command.markExecuting();
    }

    return { success: true, data: command };
  }

  async completeCommand(
    commandId: CommandId,
    result: unknown
  ): Promise<Result<void, CicadaError>> {
    const getResult = await this.deps.commandQueue.find(commandId);
    if (!getResult.success) {
      return { success: false, error: getResult.error };
    }

    const command = getResult.data;
    if (!command) {
      return {
        success: false,
        error: new CicadaError(`Command ${commandId} not found`, ErrorCode.COMMAND_NOT_FOUND, {
          severity: ErrorSeverity.MEDIUM,
        }),
      };
    }

    try {
      command.markCompleted(requireJsonValue(result, 'Command result'));
      return { success: true, data: undefined };
    } catch (error) {
      return {
        success: false,
        error: new CicadaError(
          error instanceof Error ? error.message : 'Failed to complete command',
          ErrorCode.INVALID_STATE,
          { severity: ErrorSeverity.MEDIUM }
        ),
      };
    }
  }

  async failCommand(
    commandId: CommandId,
    errorMessage: string
  ): Promise<Result<void, CicadaError>> {
    const getResult = await this.deps.commandQueue.find(commandId);
    if (!getResult.success) {
      return { success: false, error: getResult.error };
    }

    const command = getResult.data;
    if (!command) {
      return {
        success: false,
        error: new CicadaError(`Command ${commandId} not found`, ErrorCode.COMMAND_NOT_FOUND, {
          severity: ErrorSeverity.MEDIUM,
        }),
      };
    }

    command.markFailed(errorMessage);

    if (command.canRetry()) {
      command.retry();
      const requeueResult = await this.deps.commandQueue.enqueue(command);
      if (!requeueResult.success) {
        return { success: false, error: requeueResult.error };
      }
    }

    return { success: true, data: undefined };
  }

  async checkTimeouts(): Promise<Result<CommandId[], CicadaError>> {
    // This would require listing all executing commands
    // Implementation depends on CommandQueue interface extension
    return { success: true, data: [] };
  }
}
