export interface Validator<T> {
  validate(payload: T): boolean;
  getErrors(): string[];
  clear(): void;
}

