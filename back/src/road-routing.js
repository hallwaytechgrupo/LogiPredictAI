/** Trajetos rodoviarios em GeoJSON, consultados somente pelo servidor. */
// api.openrouteservice.org foi desligado pela HeiGIT em 24/11/2026 (HTTP 410).
// As mesmas chaves funcionam no endereço unificado api.heigit.org.
export const DEFAULT_DIRECTIONS_URL = 'https://api.heigit.org/openrouteservice/v2/directions/driving-car/geojson';

export function validRoutePoint(point) {
  return point && Number.isFinite(point.latitude) && Math.abs(point.latitude) <= 90 &&
    Number.isFinite(point.longitude) && Math.abs(point.longitude) <= 180;
}

export async function requestRoadRoute(waypoints, {
  apiKey = process.env.OPENROUTE_API_KEY,
  directionsUrl = process.env.OPENROUTE_DIRECTIONS_URL || DEFAULT_DIRECTIONS_URL,
  fetchImpl = (...args) => globalThis.fetch(...args),
  timeoutMs = 10000,
} = {}) {
  if (!apiKey) return { error: 'OPENROUTE_KEY_MISSING', message: 'O servico de rotas precisa ser configurado no servidor.' };
  if (!Array.isArray(waypoints) || waypoints.length < 2 || waypoints.length > 50 || !waypoints.every(validRoutePoint)) {
    return { error: 'INVALID_ROUTE_COORDINATES', message: 'Informe coordenadas validas para origem e destino.' };
  }
  try {
    const response = await fetchImpl(directionsUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: apiKey },
      body: JSON.stringify({
        coordinates: waypoints.map((point) => [point.longitude, point.latitude]),
        instructions: false,
        geometry_simplify: true,
      }),
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!response.ok) {
      if (response.status === 429) return { error: 'OPENROUTE_RATE_LIMIT', message: 'O servico de rotas atingiu seu limite de consultas. Tente novamente mais tarde.' };
      if (response.status === 401 || response.status === 403) return { error: 'OPENROUTE_UNAUTHORIZED', message: 'A chave do servico de rotas foi recusada pelo provedor.' };
      if (response.status === 410) return { error: 'OPENROUTE_GONE', message: 'O endereco do servico de rotas foi desativado pelo provedor.' };
      if (response.status === 404) return { error: 'OPENROUTE_NO_ROUTE', message: 'Nao foi encontrada uma rota rodoviaria entre os locais informados.' };
      return { error: 'OPENROUTE_ERROR', message: `O servico de rotas retornou HTTP ${response.status}.` };
    }
    const data = await response.json();
    const feature = data.features?.[0];
    const geometry = feature?.geometry;
    const coordinates = geometry?.coordinates;
    if (geometry?.type !== 'LineString' || !Array.isArray(coordinates) || coordinates.length < 2 ||
        coordinates.length > 50000 || !coordinates.every((p) => Array.isArray(p) && validRoutePoint({ longitude: p[0], latitude: p[1] }))) {
      return { error: 'OPENROUTE_NO_ROUTE', message: 'O servico nao retornou um trajeto rodoviario valido.' };
    }
    const properties = feature.properties ?? {};
    const segments = Array.isArray(properties.segments) ? properties.segments : [];
    const distance = properties.summary?.distance ?? segments.reduce((sum, p) => sum + p.distance, 0);
    const duration = properties.summary?.duration ?? segments.reduce((sum, p) => sum + p.duration, 0);
    if (!Number.isFinite(distance) || distance <= 0 || !Number.isFinite(duration) || duration < 0) {
      return { error: 'OPENROUTE_NO_ROUTE', message: 'O servico nao retornou a distancia e o tempo do trajeto.' };
    }
    return {
      distance_km: Math.round(distance / 10) / 100,
      duration_seconds: Math.round(duration),
      geometry: { type: 'LineString', coordinates: coordinates.map((p) => [p[0], p[1]]) },
    };
  } catch (error) {
    // Mensagens de rede podem conter a URL da requisicao; o cliente recebe somente o motivo publico.
    const timedOut = error.name === 'TimeoutError' || error.name === 'AbortError';
    return { error: timedOut ? 'OPENROUTE_TIMEOUT' : 'OPENROUTE_UNAVAILABLE',
      message: timedOut ? 'O servico de rotas demorou para responder. Tente novamente.' : 'O servico de rotas esta indisponivel. Tente novamente.' };
  }
}

/** Cache limitado e deduplicacao de consultas simultaneas para a mesma rota. */
export class RoadRoutingService {
  constructor({ ttlMs = 6 * 60 * 60 * 1000, maxEntries = 128, now = Date.now, ...options } = {}) {
    this.ttlMs = ttlMs;
    this.maxEntries = maxEntries;
    this.now = now;
    this.options = options;
    this.cache = new Map();
    this.pending = new Map();
  }

  async route(waypoints) {
    if (!Array.isArray(waypoints) || !waypoints.every(validRoutePoint)) {
      return { error: 'INVALID_ROUTE_COORDINATES', message: 'Informe coordenadas validas para origem e destino.' };
    }
    const key = JSON.stringify(waypoints.map((p) => [p.longitude, p.latitude]));
    const hit = this.cache.get(key);
    if (hit && hit.expires > this.now()) {
      this.cache.delete(key);
      this.cache.set(key, hit);
      return hit.route;
    }
    this.cache.delete(key);
    if (this.pending.has(key)) return this.pending.get(key);
    const pending = requestRoadRoute(waypoints, this.options).then((route) => {
      if (!route.error) {
        this.cache.set(key, { route, expires: this.now() + this.ttlMs });
        while (this.cache.size > this.maxEntries) this.cache.delete(this.cache.keys().next().value);
      }
      return route;
    }).finally(() => this.pending.delete(key));
    this.pending.set(key, pending);
    return pending;
  }
}
