/**
 * Funções utilitárias compartilhadas entre rotas e app.js.
 */

/**
 * Normaliza um CEP brasileiro para 8 dígitos.
 * Aceita formatos: 00000-000 ou 00000000.
 */
export function normalizeCep(value) {
  if (typeof value !== 'string') return null;
  const text = value.trim();
  if (!/^\d{5}-?\d{3}$/.test(text)) return null;
  return text.replace('-', '');
}

/**
 * Normaliza um order_id para string válida.
 */
export function normalizeOrderId(value) {
  if (typeof value !== 'string') return null;
  const id = value.trim();
  return id.length >= 1 && id.length <= 128 ? id : null;
}

/**
 * Calcula a distância Haversine entre dois pontos em km.
 */
export function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Parser CSV minimalista.
 */
export function parseCsvRecord(line, delimiter = ',') {
  const fields = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    if (char === '"') {
      if (quoted && line[i + 1] === '"') {
        field += '"';
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (char === delimiter && !quoted) {
      fields.push(field);
      field = '';
    } else {
      field += char;
    }
  }
  if (quoted) return null;
  fields.push(field);
  return fields;
}

export const BRAZILIAN_STATES = new Set(['AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO']);
