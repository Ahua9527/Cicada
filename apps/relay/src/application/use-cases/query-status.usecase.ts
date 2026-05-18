import type { Result } from '@cicada/shared/errors/result';
import { CicadaError, ErrorCode, ErrorSeverity } from '@cicada/shared/errors';
import type { DeviceId } from '@cicada/shared/types/common.types';
import type { DeviceStatus } from '@cicada/shared/types/device.types';
import type { SessionService } from '../services/session.service';
import type { DeviceService } from '../services/device.service';

export interface QueryStatusRequest {
  deviceId: DeviceId;
}

export interface QueryStatusResponse {
  device: DeviceStatus;
  session: {
    sessionId: string;
    isActive: boolean;
    connectedAt: number;
    lastActivity: number;
    messagesExchanged: number;
  } | null;
}

export interface QueryStatusUseCaseDeps {
  sessionService: SessionService;
  deviceService: DeviceService;
}

export class QueryStatusUseCase {
  constructor(private readonly deps: QueryStatusUseCaseDeps) {}

  async execute(request: QueryStatusRequest): Promise<Result<QueryStatusResponse, CicadaError>> {
    // 1. Get device status
    const deviceResult = await this.deps.deviceService.getDeviceStatus(request.deviceId);
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

    const deviceStatus = deviceResult.data;

    // 2. Get session info if exists
    const sessionResult = await this.deps.sessionService.getActiveSessionByDevice(request.deviceId);
    if (!sessionResult.success) {
      return { success: false, error: sessionResult.error };
    }

    const session = sessionResult.data;
    const sessionInfo =
      session && session.id
        ? {
            sessionId: session.id.toString(),
            isActive: session.isActive,
            connectedAt: session.connectedAt,
            lastActivity: session.lastActivity,
            messagesExchanged: session.messagesExchanged,
          }
        : null;

    // 3. Return combined status
    return {
      success: true,
      data: {
        device: deviceStatus,
        session: sessionInfo,
      },
    };
  }
}
