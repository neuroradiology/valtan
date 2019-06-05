import { toLispBoolean } from './header';
import { values1 } from './values';

export function CL_eq(x, y) {
  return values1(toLispBoolean(x === y));
}

export function CL_error(string) {
  throw new Error(string);
}

export class BlockValue {
  constructor(symbol, value) {
    this.name = symbol;
    this.value = value;
  }
}

export class TagValue {
  constructor(level, index) {
    this.level = level;
    this.index = index;
  }
}

export class CatchValue {
  constructor(symbol, value) {
    this.symbol = symbol;
    this.value = value;
  }
}