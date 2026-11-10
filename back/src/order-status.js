export const ORDER_STATUSES = new Set([
  'pending', 'created', 'approved', 'invoiced', 'processing', 'shipped',
  'delivered', 'canceled', 'unavailable', 'unknown',
]);

// Sem um status informado, o despacho é a única evidência disponível do andamento.
export function orderStatus(order) {
  const value = typeof order === 'string' ? order : order?.status ?? order?.order_status;
  const status = typeof value === 'string' ? value.trim().toLowerCase() : '';
  return status || (order?.dispatched_at ? 'shipped' : 'unknown');
}
