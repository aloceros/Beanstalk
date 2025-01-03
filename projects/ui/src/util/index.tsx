// -----------------
// Exports
// -----------------

export * from './Account';
export * from './Actions';
export * from './BeaNFTs';
export * from './BigNumber';
export * from './Chain';
export * from './wagmi/Client';
export * from './Crates';
// export * from './Curve';
export * from './Farm';
export * from './Governance';
export * from './Guides';
export * from './Ledger';
export * from './Season';
export * from './State';
export * from './Time';
export * from './Tokens';
export * from './Environment';
export * from './TokenValue';
export * from './UI';

// -----------------
// Shared Types
// -----------------

export type SeasonMap<T> = { [season: string]: T };
export type PlotMap<T> = { [index: string]: T };

// -----------------
// Other Helpers
// -----------------

const ordinalRulesEN = new Intl.PluralRules('en', { type: 'ordinal' });
const suffixes: { [k: string]: string } = {
  one: 'st',
  two: 'nd',
  few: 'rd',
  other: 'th',
};

export function ordinal(number: number): string {
  const category = ordinalRulesEN.select(number);
  const suffix = suffixes[category];
  return number + suffix;
}

export function isSetObject(obj: unknown): obj is Set<unknown> {
  return (
    obj instanceof Set && Object.prototype.toString.call(obj) === '[object Set]'
  );
}

export function arrayifyIfSet<T>(obj: T[] | Set<T>): T[] {
  return Array.isArray(obj) ? obj : [...obj];
}

export function isFunction<T extends Function>(value: any): value is T {
  return typeof value === 'function';
}

export function mayFunctionToValue<T>(valueOrFunction: any, ...vars: any[]): T {
  if (isFunction(valueOrFunction)) {
    return valueOrFunction(...vars) satisfies T;
  }

  return valueOrFunction satisfies T;
}
