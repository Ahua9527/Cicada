import type { JsonValue, DeviceId } from '@cicada/shared/types/common.types';
import type { CommandType, CommandParams } from '@cicada/shared/types/command.types';

const COMMAND_ID_PATTERN = /^CMD_[0-9a-fA-F]{32}$/;

export enum CommandStatus {
  PENDING = 'pending',
  QUEUED = 'queued',
  EXECUTING = 'executing',
  COMPLETED = 'completed',
  FAILED = 'failed',
  TIMEOUT = 'timeout',
  CANCELLED = 'cancelled',
}

export enum CommandPriority {
  LOW = 'low',
  NORMAL = 'normal',
  HIGH = 'high',
}

export class CommandId {
  private constructor(private readonly value: string) {}

  static create(raw: string): CommandId | null {
    return COMMAND_ID_PATTERN.test(raw) ? new CommandId(raw) : null;
  }

  static generate(): CommandId {
    const cryptoApi =
      typeof globalThis !== 'undefined' ? (globalThis as { crypto?: Crypto }).crypto : undefined;

    if (cryptoApi && typeof cryptoApi.getRandomValues === 'function') {
      const bytes = cryptoApi.getRandomValues(new Uint8Array(16));
      const hex = Array.from(bytes)
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
      return new CommandId(`CMD_${hex}`);
    }

    let fallback = '';
    for (let i = 0; i < 32; i += 1) {
      fallback += Math.floor(Math.random() * 16).toString(16);
    }
    return new CommandId(`CMD_${fallback}`);
  }

  toString(): string {
    return this.value;
  }

  equals(other: CommandId): boolean {
    return this.value === other.value;
  }
}

export class CommandTimestamp {
  private constructor(private readonly value: number) {}

  static now(): CommandTimestamp {
    return new CommandTimestamp(Date.now());
  }

  static create(raw: number | null | undefined): CommandTimestamp | null {
    return raw != null && Number.isFinite(raw) && raw >= 0 ? new CommandTimestamp(raw) : null;
  }

  toNumber(): number {
    return this.value;
  }

  diff(other: CommandTimestamp): number {
    return this.value - other.value;
  }
}

export type CommandProps = {
  commandId?: CommandId | null;
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

type InternalState = {
  commandId: CommandId;
  deviceId: DeviceId;
  type: CommandType;
  params: CommandParams;
  createdAt: CommandTimestamp;
  queuedAt: CommandTimestamp | null;
  executingAt: CommandTimestamp | null;
  completedAt: CommandTimestamp | null;
  status: CommandStatus;
  priority: CommandPriority;
  retryCount: number;
  maxRetries: number;
  timeoutMs: number;
  nonce: string | null;
  error: string | null;
  result: JsonValue | null;
};

export class Command {
  private state: InternalState;

  private constructor(state: InternalState) {
    this.state = state;
  }

  static create(props: CommandProps): Command {
    const commandId = props.commandId ?? CommandId.generate();
    const createdAt = CommandTimestamp.create(props.createdAt) ?? CommandTimestamp.now();
    const queuedAt = CommandTimestamp.create(props.queuedAt ?? null);
    const executingAt = CommandTimestamp.create(props.executingAt ?? null);
    const completedAt = CommandTimestamp.create(props.completedAt ?? null);

    return new Command({
      commandId,
      deviceId: props.deviceId,
      type: props.type,
      params: props.params ?? {},
      createdAt,
      queuedAt,
      executingAt,
      completedAt,
      status: props.status ?? CommandStatus.PENDING,
      priority: props.priority ?? CommandPriority.NORMAL,
      retryCount: props.retryCount ?? 0,
      maxRetries: props.maxRetries ?? 3,
      timeoutMs: props.timeoutMs ?? 30000,
      nonce: props.nonce ?? null,
      error: props.error ?? null,
      result: props.result ?? null,
    });
  }

  get id(): CommandId {
    return this.state.commandId;
  }

  get deviceId(): DeviceId {
    return this.state.deviceId;
  }

  get type(): CommandType {
    return this.state.type;
  }

  get params(): CommandParams {
    return { ...this.state.params };
  }

  get status(): CommandStatus {
    return this.state.status;
  }

  get priority(): CommandPriority {
    return this.state.priority;
  }

  get createdAt(): number {
    return this.state.createdAt.toNumber();
  }

  get error(): string | null {
    return this.state.error;
  }

  get result(): JsonValue | null {
    return this.state.result;
  }

  get retryCount(): number {
    return this.state.retryCount;
  }

  get maxRetries(): number {
    return this.state.maxRetries;
  }

  markQueued(at: number = Date.now()): void {
    if (this.state.status !== CommandStatus.PENDING) {
      throw new Error(`Cannot queue command in status: ${this.state.status}`);
    }
    this.state.queuedAt = CommandTimestamp.create(at) ?? CommandTimestamp.now();
    this.state.status = CommandStatus.QUEUED;
  }

  markExecuting(at: number = Date.now()): void {
    if (this.state.status !== CommandStatus.QUEUED && this.state.status !== CommandStatus.PENDING) {
      throw new Error(`Cannot execute command in status: ${this.state.status}`);
    }
    this.state.executingAt = CommandTimestamp.create(at) ?? CommandTimestamp.now();
    this.state.status = CommandStatus.EXECUTING;
  }

  markCompleted(result: JsonValue, at: number = Date.now()): void {
    if (this.state.status !== CommandStatus.EXECUTING) {
      throw new Error(`Cannot complete command in status: ${this.state.status}`);
    }
    this.state.completedAt = CommandTimestamp.create(at) ?? CommandTimestamp.now();
    this.state.status = CommandStatus.COMPLETED;
    this.state.result = result;
    this.state.error = null;
  }

  markFailed(error: string, at: number = Date.now()): void {
    this.state.completedAt = CommandTimestamp.create(at) ?? CommandTimestamp.now();
    this.state.status = CommandStatus.FAILED;
    this.state.error = error;
  }

  markTimeout(at: number = Date.now()): void {
    this.state.completedAt = CommandTimestamp.create(at) ?? CommandTimestamp.now();
    this.state.status = CommandStatus.TIMEOUT;
    this.state.error = `Command timed out after ${this.state.timeoutMs}ms`;
  }

  markCancelled(at: number = Date.now()): void {
    this.state.completedAt = CommandTimestamp.create(at) ?? CommandTimestamp.now();
    this.state.status = CommandStatus.CANCELLED;
    this.state.error = 'Command cancelled';
  }

  canRetry(): boolean {
    return (
      (this.state.status === CommandStatus.FAILED || this.state.status === CommandStatus.TIMEOUT) &&
      this.state.retryCount < this.state.maxRetries
    );
  }

  retry(): void {
    if (!this.canRetry()) {
      throw new Error('Command cannot be retried');
    }
    this.state.retryCount += 1;
    this.state.status = CommandStatus.PENDING;
    this.state.executingAt = null;
    this.state.completedAt = null;
    this.state.error = null;
  }

  hasTimedOut(now: number = Date.now()): boolean {
    if (this.state.status !== CommandStatus.EXECUTING) {
      return false;
    }
    if (!this.state.executingAt) {
      return false;
    }
    const timestamp = CommandTimestamp.create(now) ?? CommandTimestamp.now();
    return timestamp.diff(this.state.executingAt) > this.state.timeoutMs;
  }

  getExecutionTime(): number | null {
    if (!this.state.executingAt || !this.state.completedAt) {
      return null;
    }
    return this.state.completedAt.diff(this.state.executingAt);
  }

  isTerminal(): boolean {
    return [
      CommandStatus.COMPLETED,
      CommandStatus.FAILED,
      CommandStatus.TIMEOUT,
      CommandStatus.CANCELLED,
    ].includes(this.state.status);
  }
}
