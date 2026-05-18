/**
 * Command Controller
 * Handles command sending and execution
 */

import type { MiddlewareContext, WebSocketMessage, ApiResponse } from '../../types';

const createMessageId = (): string =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : `msg-${Date.now()}-${Math.random().toString(16).slice(2)}`;

/**
 * Command Controller
 */
export class CommandController {
  /**
   * Send command to device
   */
  static async sendCommand(context: MiddlewareContext): Promise<Response> {
    const { env, logger, requestId, validatedRequest } = context;

    if (!validatedRequest) {
      return Response.json(
        {
          ok: false,
          error: 'Request validation failed',
        },
        { status: 400 }
      );
    }

    const { device_id, cmd } = validatedRequest;
    const now = Date.now();
    const messageTs =
      typeof validatedRequest.ts === 'number' && Number.isFinite(validatedRequest.ts)
        ? validatedRequest.ts
        : now;

    try {
      // Get device's Durable Object
      const sessionId = env.CICADA_SESSIONS.idFromName(device_id);
      const sessionManager = await env.CICADA_SESSIONS.get(sessionId);

      // Build WebSocket message
      const message: WebSocketMessage = {
        id: createMessageId(),
        timestamp: now,
        type: 'command',
        cmd,
        ts: messageTs,
        data: {
          ...(validatedRequest.params ?? {}),
          command: cmd,
          cmd,
        },
      };

      // Send command to device
      const sendResponse = await sessionManager.fetch('http://session/send', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': device_id,
        },
        body: JSON.stringify(message),
      });

      const result = (await sendResponse.json()) as {
        success: boolean;
        error?: string;
        commandId?: string;
        timestamp?: number;
      };

      logger.info('Command sent', {
        requestId,
        context: {
          deviceId: device_id,
          command: cmd,
          success: result.success,
        },
        tags: ['command', 'send'],
      });

      return Response.json({
        ok: result.success,
        message: result.success ? 'Command sent' : result.error,
        data: result.success
          ? {
              command_id: result.commandId,
              device_id: device_id,
              status: result.success ? 'sent' : 'failed',
              timestamp: result.timestamp ?? Date.now(),
            }
          : undefined,
      } satisfies ApiResponse);
    } catch (error) {
      logger.error('Command sending failed', {
        requestId,
        error: error as Error,
        context: { deviceId: device_id, command: cmd },
        tags: ['command', 'error'],
      });

      return Response.json(
        {
          ok: false,
          error: 'Command sending failed',
        },
        { status: 500 }
      );
    }
  }
}
