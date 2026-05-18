import type { Result } from '@cicada/shared/errors/result';
import { CicadaError, ErrorCode, ErrorSeverity } from '@cicada/shared/errors';
import type { DeviceId } from '@cicada/shared/types/common.types';
import type { CommandType, CommandParams } from '@cicada/shared/types/command.types';
import { CommandPriority } from '../../domain/command/command.entity';
import type { SessionService } from '../services/session.service';
import type { CommandService } from '../services/command.service';
import type { DeviceService } from '../services/device.service';

export interface SendCommandRequest {
  deviceId: DeviceId;
  commandType: CommandType;
  params?: CommandParams;
  priority?: CommandPriority;
  maxRetries?: number;
  timeoutMs?: number;
}

export interface SendCommandResponse {
  commandId: string;
  status: string;
  queuedAt: number;
}

export interface SendCommandUseCaseDeps {
  sessionService: SessionService;
  commandService: CommandService;
  deviceService: DeviceService;
}

export class SendCommandUseCase {
  constructor(private readonly deps: SendCommandUseCaseDeps) {}

  async execute(request: SendCommandRequest): Promise<Result<SendCommandResponse, CicadaError>> {
    // 1. Verify device exists
    const deviceResult = await this.deps.deviceService.getDevice(request.deviceId);
    if (!deviceResult.success) {
      return { success: false, error: deviceResult.error };
    }

    if (!deviceResult.data) {
      return {
        success: false,
        error: new CicadaError(
          `Device ${request.deviceId} not found`,
          ErrorCode.DEVICE_NOT_FOUND,
          { severity: ErrorSeverity.MEDIUM }
        ),
      };
    }

    // 2. Check if device is connected
    const device = deviceResult.data;
    if (!device.isConnected) {
      return {
        success: false,
        error: new CicadaError(
          `Device ${request.deviceId} is not connected`,
          ErrorCode.DEVICE_OFFLINE,
          { severity: ErrorSeverity.MEDIUM }
        ),
      };
    }

    // 3. Verify active session exists
    const sessionResult = await this.deps.sessionService.getActiveSessionByDevice(request.deviceId);
    if (!sessionResult.success) {
      return { success: false, error: sessionResult.error };
    }

    if (!sessionResult.data) {
      return {
        success: false,
        error: new CicadaError(
          `No active session for device ${request.deviceId}`,
          ErrorCode.SESSION_NOT_FOUND,
          { severity: ErrorSeverity.MEDIUM }
        ),
      };
    }

    // 4. Create and enqueue command
    const commandResult = await this.deps.commandService.createCommand(
      request.deviceId,
      request.commandType,
      request.params,
      {
        priority: request.priority,
        maxRetries: request.maxRetries,
        timeoutMs: request.timeoutMs,
      }
    );

    if (!commandResult.success) {
      return { success: false, error: commandResult.error };
    }

    const command = commandResult.data;

    // 5. Return response
    return {
      success: true,
      data: {
        commandId: command.id.toString(),
        status: command.status,
        queuedAt: command.createdAt,
      },
    };
  }
}
