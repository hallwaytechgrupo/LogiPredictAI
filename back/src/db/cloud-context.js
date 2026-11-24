import { AsyncLocalStorage } from 'node:async_hooks';

const context = new AsyncLocalStorage();

export function cloudStore() {
  return context.getStore()?.store ?? null;
}

export function cloudRequest(store, operation) {
  return context.run({ store, versions: new Map() }, operation);
}

export function collectionVersions() {
  return context.getStore()?.versions;
}
