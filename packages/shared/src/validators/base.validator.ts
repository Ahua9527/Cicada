import type { Validator } from './validator.interface';

export abstract class BaseValidator<T> implements Validator<T> {
  protected errors: string[] = [];

  abstract validate(payload: T): boolean;

  protected addError(message: string): void {
    this.errors.push(message);
  }

  getErrors(): string[] {
    return [...this.errors];
  }

  clear(): void {
    this.errors = [];
  }
}

