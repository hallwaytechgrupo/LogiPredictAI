/**
 * Backend API do LogiPredictAI — servidor Express com roteamento REST.
 *
 * Fornece endpoints para:
 * - Previsão de risco de atraso (integração com o serviço ML FastAPI).
 * - Gerenciamento de hubs logísticos (CRUD).
 * - Gerenciamento de pedidos (criação, listagem, atualização).
 * - Histórico de previsões com deduplicação por journal (JSONL).
 * - Análise geográfica: agregação por região e UF.
 * - Simulação de despacho com alocação de hubs.
 * - Importação de dados Olist a partir de CSV.
 *
 * Dados são persistidos em arquivos JSON locais (orders.json, predictions.json, hubs.json).
 * Mutações são serializadas para evitar condições de corrida.
 */
import express from 'express';
import helmet from 'helmet';
import { randomUUID } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { appendFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';

// Repositórios PostgreSQL (fallback para JSON)
import {
  create as createPrediction,
  findByOrderId as findPredictionsByOrderId,
  list as listPredictions,
  checkDb as checkPredictionsDb,
} from './db/repositories/predictions.js';
import {
  findById as findOrderById,
  list as listOrders,
  checkDb as checkOrdersDb,
} from './db/repositories/orders.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_HUBS_FILE = path.resolve(process.cwd(), 'data', 'hubs.json');

/**
 * Cria e configura a aplicação Express com todos os roteadores e middleware.
 *
 * @param {Object} opts - Configurações opcionais.
 * @param {string} opts.mlUrl - URL do serviço ML FastAPI.
 * @param {number} opts.timeoutMs - Timeout em ms para chamadas ao ML.
 * @param {string} opts.hubsFile - Caminho para hubs.json.
 * @param {string} opts.ordersFile - Caminho para orders.json.
 * @param {string} opts.predictionsFile - Caminho para predictions.json.
 * @param {string} opts.predictionJournalFile - Caminho para predictions.jsonl.
 * @param {string} opts.olistDatasetFile - Caminho para pedidos_logipredict.csv.
 * @param {string} opts.geolocationFile - Caminho para olist_geolocation_dataset.csv.
 * @param {string} opts.olistOrdersFile - Caminho para olist_orders_dataset.csv.
 * @param {string} opts.olistCustomersFile - Caminho para olist_customers_dataset.csv.
 * @param {number} opts.batchConcurrency - Concorrência máxima para previsões em lote.
 * @param {number} opts.batchSize - Tamanho do lote para importação Olist.
 * @returns {import('express').Express} Aplicação Express configurada.
 */
export async function createApp({
  mlUrl = 'http://127.0.0.1:8000',
  timeoutMs = 10000,
  hubsFile = process.env.HUBS_FILE || DEFAULT_HUBS_FILE,
  ordersFile = process.env.ORDERS_FILE || path.resolve(process.cwd(), 'data', 'orders.json'),
  predictionsFile = process.env.PREDICTIONS_FILE || path.resolve(process.cwd(), 'data', 'predictions.json'),
  predictionJournalFile = process.env.PREDICTIONS_JOURNAL_FILE || `${predictionsFile}.jsonl`,
  olistDatasetFile = process.env.OLIST_DATASET_FILE || path.resolve(process.cwd(), 'data', 'pedidos_logipredict.csv'),
  geolocationFile = process.env.GEOLOCATION_FILE || path.resolve(process.cwd(), 'data', 'raw', 'olist_geolocation_dataset.csv'),
  olistOrdersFile = process.env.OLIST_ORDERS_FILE || path.resolve(process.cwd(), 'data', 'raw', 'olist_orders_dataset.csv'),
  olistCustomersFile = process.env.OLIST_CUSTOMERS_FILE || path.resolve(process.cwd(), 'data', 'raw', 'olist_customers_dataset.csv'),
  batchConcurrency = parseInt(process.env.BATCH_CONCURRENCY, 10) || 5,
  batchSize = parseInt(process.env.BATCH_SIZE, 10) || 200,
} = {}) {
  const app = express();
  app.disable('x-powered-by');
  app.use(helmet());

  // Permitir chamadas do Flutter Web durante o desenvolvimento local.
  app.use((req, res, next) => {
    const origin = req.headers.origin;

    if (origin && /^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(origin)) {
      res.setHeader('Access-Control-Allow-Origin', origin);
      res.vary('Origin');
      res.setHeader(
        'Access-Control-Allow-Methods',
        'GET, POST, PUT, PATCH, DELETE, OPTIONS'
      );
      res.setHeader(
        'Access-Control-Allow-Headers',
        'Content-Type, Accept'
      );

      if (req.method === 'OPTIONS') {
        return res.sendStatus(204);
      }
    }

    next();
  });
  app.use('/api/v1/predictions/batch', express.json({ limit: '10mb', strict: true }));
  app.use(express.json({ limit: '2mb', strict: true }));
  // Fila de serialização: garante que mutações em orders.json sejam executadas sequencialmente,
  // evitando condições de corrida quando múltiplas requisições modificam o arquivo simultaneamente.
  let geolocationIndexPromise;
  let orderMutationQueue = Promise.resolve();
  let predictionMutationQueue = Promise.resolve();
  let predictionJournalValidated = false;

  /**
   * Serializa operações de mutação em orders.json.
   * Garante que apenas uma operação por vez modifique o arquivo de pedidos.
   */
  function serializeOrderMutation(operation) {
    const task = orderMutationQueue.then(operation, operation);
    orderMutationQueue = task.then(() => undefined, () => undefined);
    return task;
  }

  /**
   * Serializa operações de mutação em predictions.json.
   * Garante que apenas uma operação por vez modifique o arquivo de previsões.
   */
  function serializePredictionMutation(operation) {
    const task = predictionMutationQueue.then(operation, operation);
    predictionMutationQueue = task.then(() => undefined, () => undefined);
    return task;
  }

  /**
   * Parser CSV minimalista sem dependências externas.
   * Suporta campos entre aspas com aspas escapadas ("").
   *
   * @param {string} line - Linha CSV a ser parseada.
   * @returns {string[]|null} Array de campos ou null se a linha estiver malformada.
   */
  function parseCsvRecord(line) {
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
      } else if (char === ',' && !quoted) {
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

  /**
   * Carrega o índice de geolocalização a partir do CSV da Olist.
   * Lê o arquivo linha a linha (stream) para economizar memória.
   * Agrupa por CEP e calcula mediana de lat/lng e moda de cidade/UF.
   *
   * @returns {Map<string, Object>} Mapa CEP -> {latitude, longitude, city, state}.
   */
  async function loadGeolocationIndex() {
    const groups = new Map();
    const stream = createReadStream(geolocationFile, { encoding: 'utf8' });
    const lines = createInterface({ input: stream, crlfDelay: Infinity });
    let columns;
    for await (const line of lines) {
      const row = parseCsvRecord(line);
      if (!row) continue;
      if (!columns) {
        columns = new Map(row.map((name, index) => [name.trim().toLowerCase(), index]));
        continue;
      }
      const at = (name) => row[columns.get(name)]?.trim() ?? '';
      const prefix = at('geolocation_zip_code_prefix').padStart(5, '0');
      const latitude = Number(at('geolocation_lat'));
      const longitude = Number(at('geolocation_lng'));
      if (!/^\d{5}$/.test(prefix) || !Number.isFinite(latitude) ||
          latitude < -90 || latitude > 90 || !Number.isFinite(longitude) ||
          longitude < -180 || longitude > 180) continue;
      let group = groups.get(prefix);
      if (!group) {
        group = { latitudes: [], longitudes: [], cities: new Map(), states: new Map() };
        groups.set(prefix, group);
      }
      group.latitudes.push(latitude);
      group.longitudes.push(longitude);
      const city = at('geolocation_city');
      const state = at('geolocation_state').toUpperCase();
      if (city) group.cities.set(city, (group.cities.get(city) ?? 0) + 1);
      if (state) group.states.set(state, (group.states.get(state) ?? 0) + 1);
    }
    const median = (values) => {
      values.sort((a, b) => a - b);
      const middle = Math.floor(values.length / 2);
      return values.length % 2 ? values[middle] : (values[middle - 1] + values[middle]) / 2;
    };
    const mode = (values) => [...values.entries()]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]?.[0] ?? '';
    for (const [prefix, group] of groups) {
      groups.set(prefix, {
        latitude: median(group.latitudes),
        longitude: median(group.longitudes),
        city: mode(group.cities),
        state: mode(group.states),
      });
    }
    return groups;
  }

  /**
   * Retorna o índice de geolocalização, carregando sob demanda (lazy loading).
   * Em cache após o primeiro carregamento bem-sucedido.
   *
   * @returns {Map<string, Object>} Mapa CEP -> {latitude, longitude, city, state}.
   */
  async function getGeolocationIndex() {
    if (!geolocationIndexPromise) {
      geolocationIndexPromise = loadGeolocationIndex().catch((error) => {
        geolocationIndexPromise = null;
        throw error;
      });
    }
    return geolocationIndexPromise;
  }

  /* ---- Helpers de classificação de risco e geografia ---- */

  // Limiares de taxa de atraso (%) para classificação de risco por região/UF.
  const RISK_THRESHOLDS = { low: 10, medium: 20, high: 30 };

  /**
   * Classifica o risco de atraso com base na taxa observada.
   * Categorias: baixo (<=10%), médio (<=20%), alto (<=30%), muito_alto (>30%).
   *
   * @param {number} ordersWithValidDates - Total de pedidos com datas válidas.
   * @param {number} delayedOrders - Quantidade de pedidos atrasados.
   * @returns {string} Categoria de risco: 'baixo', 'medio', 'alto', 'muito_alto' ou 'sem_dados'.
   */
  function classifyOrderRisk(ordersWithValidDates, delayedOrders) {
    if (ordersWithValidDates === 0) return 'sem_dados';
    const rate = (delayedOrders / ordersWithValidDates) * 100;
    if (rate <= RISK_THRESHOLDS.low) return 'baixo';
    if (rate <= RISK_THRESHOLDS.medium) return 'medio';
    if (rate <= RISK_THRESHOLDS.high) return 'alto';
    return 'muito_alto';
  }

  async function loadOrdersDataset() {
    const orders = [];
    const stream = createReadStream(olistOrdersFile, { encoding: 'utf8' });
    const lines = createInterface({ input: stream, crlfDelay: Infinity });
    let columns;
    for await (const line of lines) {
      const row = parseCsvRecord(line);
      if (!row) continue;
      if (!columns) {
        columns = new Map(row.map((name, index) => [name.trim().toLowerCase(), index]));
        continue;
      }
      const at = (name) => row[columns.get(name)]?.trim() ?? '';
      orders.push({
        order_id: at('order_id'),
        customer_id: at('customer_id'),
        delivered_date: at('order_delivered_customer_date'),
        estimated_date: at('order_estimated_delivery_date'),
      });
    }
    return orders;
  }

  async function loadCustomersDataset() {
    const customers = new Map();
    const stream = createReadStream(olistCustomersFile, { encoding: 'utf8' });
    const lines = createInterface({ input: stream, crlfDelay: Infinity });
    let columns;
    for await (const line of lines) {
      const row = parseCsvRecord(line);
      if (!row) continue;
      if (!columns) {
        columns = new Map(row.map((name, index) => [name.trim().toLowerCase(), index]));
        continue;
      }
      const at = (name) => row[columns.get(name)]?.trim() ?? '';
      const customerId = at('customer_id');
      if (!customerId) continue;
      customers.set(customerId, {
        customer_id: customerId,
        zip_code_prefix: at('customer_zip_code_prefix').padStart(5, '0'),
        city: at('customer_city'),
        state: at('customer_state').toUpperCase(),
      });
    }
    return customers;
  }

  function normalizeCep(value) {
    if (typeof value !== 'string') return null;
    const text = value.trim();
    if (!/^\d{5}-?\d{3}$/.test(text)) return null;
    return text.replace('-', '');
  }

  function haversineKm(origin, destination) {
    const radians = (degrees) => degrees * Math.PI / 180;
    const lat1 = radians(origin.latitude);
    const lat2 = radians(destination.latitude);
    const deltaLat = radians(destination.latitude - origin.latitude);
    const deltaLng = radians(destination.longitude - origin.longitude);
    const a = Math.sin(deltaLat / 2) ** 2 +
      Math.cos(lat1) * Math.cos(lat2) * Math.sin(deltaLng / 2) ** 2;
    return 6371.0088 * 2 * Math.asin(Math.sqrt(Math.min(1, a)));
  }

  async function readHubs() {
    try {
      const content = await readFile(hubsFile, 'utf8');
      const parsed = JSON.parse(content);
      if (!Array.isArray(parsed)) throw new Error('Formato de hubs.json inválido.');
      return parsed.map((hub) => ({
        ...hub,
        validationStatus: hub.validationStatus ?? 'APROVADO',
      }));
    } catch (error) {
      if (error.code === 'ENOENT') return [];
      throw error;
    }
  }

  async function writeHubs(hubs) {
    await mkdir(path.dirname(hubsFile), { recursive: true });
    const temp = `${hubsFile}.${process.pid}.tmp`;
    await writeFile(temp, `${JSON.stringify(hubs, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
    const { rename } = await import('node:fs/promises');
    await rename(temp, hubsFile);
  }

  async function readOrders() {
    // Tenta PostgreSQL primeiro; se indisponível, fallback para JSON.
    // Mescla resultados do DB e do JSON para suportar testes que usam JSON.
    let dbOrders = [];
    const dbOk = await checkOrdersDb();
    if (dbOk) {
      try {
        const result = await listOrders({ page: 1, perPage: 50000 });
        if (result && result.data) dbOrders = result.data;
      } catch (e) {
        console.warn('Falha ao ler pedidos do PostgreSQL, usando JSON:', e.message);
      }
    }
    let jsonOrders = [];
    try {
      const content = await readFile(ordersFile, 'utf8');
      const parsed = JSON.parse(content);
      if (Array.isArray(parsed)) jsonOrders = parsed;
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    // Mescla DB + JSON, deduplicando por order_id (DB tem prioridade)
    if (jsonOrders.length === 0) return dbOrders;
    if (dbOrders.length === 0) return jsonOrders;
    const seen = new Set(dbOrders.map((o) => o.order_id));
    const merged = [...dbOrders];
    for (const jo of jsonOrders) {
      if (!seen.has(jo.order_id)) {
        merged.push(jo);
        seen.add(jo.order_id);
      }
    }
    return merged;
  }

  async function writeOrders(orders) {
    await mkdir(path.dirname(ordersFile), { recursive: true });
    const temp = `${ordersFile}.${process.pid}.tmp`;
    await writeFile(temp, `${JSON.stringify(orders, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
    const { rename } = await import('node:fs/promises');
    await rename(temp, ordersFile);
  }

  async function readPredictions() {
    // Tenta PostgreSQL primeiro; se indisponível, fallback para JSON/JSONL.
    const dbOk = await checkPredictionsDb();
    if (dbOk) {
      try {
        const result = await listPredictions({ page: 1, perPage: 50000 });
        if (result && result.data) return result.data;
      } catch (e) {
        console.warn('Falha ao ler previsões do PostgreSQL, usando JSON:', e.message);
      }
    }
    let history = [];
    try {
      const content = await readFile(predictionsFile, 'utf8');
      const parsed = JSON.parse(content);
      if (!Array.isArray(parsed)) throw new Error('Formato de predictions.json inválido.');
      history = parsed;
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    try {
      const journal = await readFile(predictionJournalFile, 'utf8');
      for (const [index, line] of journal.split('\n').entries()) {
        if (!line.trim()) continue;
        try {
          const prediction = JSON.parse(line);
          if (!prediction || typeof prediction !== 'object' || Array.isArray(prediction)) {
            throw new Error('Registro deve ser um objeto JSON.');
          }
          history.push(prediction);
        } catch {
          throw new Error(`Registro inválido na linha ${index + 1} de predictions.jsonl.`);
        }
      }
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    return history;
  }

  async function appendPrediction(prediction) {
    // Tenta PostgreSQL primeiro; se indisponível, fallback para JSONL.
    const dbOk = await checkPredictionsDb();
    if (dbOk) {
      try {
        await createPrediction(prediction);
        return;
      } catch (e) {
        console.warn('Falha ao salvar previsão no PostgreSQL, usando JSONL:', e.message);
      }
    }
    return serializePredictionMutation(async () => {
      // Validate the existing history once; subsequent predictions append in O(1).
      if (!predictionJournalValidated) {
        await readPredictions();
        predictionJournalValidated = true;
      }
      await mkdir(path.dirname(predictionJournalFile), { recursive: true });
      await appendFile(predictionJournalFile, `${JSON.stringify(prediction)}\n`, { encoding: 'utf8', mode: 0o600 });
    });
  }

  function normalizeOrderId(value) {
    if (typeof value !== 'string') return null;
    const id = value.trim();
    return id.length >= 1 && id.length <= 128 ? id : null;
  }

  async function validateHubReference(hubId, hubsSnapshot) {
    if (hubId === null) return { hub: null };
    if (typeof hubId !== 'string' || !hubId.trim() || hubId.length > 128) {
      return { error: { status: 422, code: 'INVALID_HUB_ID', message: 'hub_id deve ser um identificador de hub válido ou null.' } };
    }
    const hubs = hubsSnapshot ?? await readHubs();
    const hub = hubs.find((candidate) => candidate.id === hubId.trim());
    if (!hub) return { error: { status: 404, code: 'HUB_NOT_FOUND', message: 'O hub informado não existe.' } };
    return { hub };
  }

  const BRAZILIAN_STATES = new Set(['AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO']);

  function normalizeStatesServed(value, existingValue) {
    // Returns { statesServed: string[] | null, errors: array }
    const errors = [];
    let statesServed = existingValue ?? null;
    if (value === undefined) {
      return { statesServed, errors };
    }
    if (value === null || value === '') {
      statesServed = null;
      return { statesServed, errors };
    }
    if (!Array.isArray(value)) {
      errors.push({ field: 'statesServed', message: 'states_served deve ser uma lista de UFs.' });
      return { statesServed, errors };
    }
    const normalized = [];
    for (const item of value) {
      if (typeof item !== 'string') {
        errors.push({ field: 'statesServed', message: 'Cada UF deve ser uma string.' });
        continue;
      }
      const uf = item.trim().toUpperCase();
      if (!BRAZILIAN_STATES.has(uf)) {
        errors.push({ field: 'statesServed', message: `"${item}" não é uma UF brasileira válida.` });
        continue;
      }
      normalized.push(uf);
    }
    const unique = [...new Set(normalized)].sort();
    statesServed = unique.length > 0 ? unique : null;
    return { statesServed, errors };
  }

  function normalizeHub(body, existing = {}) {
    const code = String(body.code ?? existing.code ?? '').trim().toUpperCase();
    const name = String(body.name ?? existing.name ?? '').trim();
    const city = String(body.city ?? existing.city ?? '').trim();
    const state = String(body.state ?? existing.state ?? '').trim().toUpperCase();
    const validationStatus = String(body.validationStatus ?? existing.validationStatus ?? 'APROVADO');
    const errors = [];
    if (!/^[A-Z0-9_-]{2,32}$/.test(code)) errors.push({ field: 'code', message: 'Use 2 a 32 caracteres: letras, números, hífen ou sublinhado.' });
    if (name.length < 2 || name.length > 100) errors.push({ field: 'name', message: 'O nome deve ter entre 2 e 100 caracteres.' });
    if (!['PENDENTE_VALIDACAO', 'APROVADO', 'REJEITADO'].includes(validationStatus)) {
      errors.push({ field: 'validationStatus', message: 'Estado de validação inválido.' });
    }
    if ((validationStatus === 'APROVADO' && city.length < 2) || city.length > 80) {
      errors.push({ field: 'city', message: 'Informe uma cidade válida para aprovar o hub.' });
    }
    if (!BRAZILIAN_STATES.has(state)) errors.push({ field: 'state', message: 'Informe uma UF brasileira válida.' });

    // Handle statesServed
    const { statesServed, errors: ssErrors } = normalizeStatesServed(body.statesServed, existing.statesServed);
    errors.push(...ssErrors);

    const optionalTextFields = [
      'osmId', 'provisionalCategory', 'osmTags', 'operator', 'owner', 'brand',
      'osmUrl', 'classification', 'justification',
    ];
    const hub = { ...existing, code, name, city, state, validationStatus, statesServed };
    for (const field of optionalTextFields) {
      if (body[field] !== undefined) {
        hub[field] = body[field] == null || body[field] === '' ? null : String(body[field]).trim();
      }
    }
    for (const field of ['latitude', 'longitude']) {
      if (body[field] !== undefined) {
        const value = body[field] == null || body[field] === '' ? null : Number(body[field]);
        const valid = value == null || (Number.isFinite(value) &&
          (field === 'latitude' ? value >= -90 && value <= 90 : value >= -180 && value <= 180));
        if (!valid) errors.push({ field, message: 'Coordenada inválida.' });
        else hub[field] = value;
      }
    }
    if ((hub.latitude == null) !== (hub.longitude == null)) {
      errors.push({ field: 'coordinates', message: 'Informe latitude e longitude juntas.' });
    }
    return { hub, errors };
  }

  function handleStorageError(res, error) {
    // Do not expose local filesystem paths or internal exception details.
    console.error('Falha no armazenamento de hubs:', error.message);
    return res.status(500).json({ error: 'HUB_STORAGE_ERROR', message: 'Não foi possível acessar o cadastro de hubs.' });
  }

  function proxy(pathname, method = 'GET') {
    return async (req, res) => {
      if (method === 'POST' && !req.is('application/json')) {
        return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
      }
      try {
        const upstream = await fetch(new URL(pathname, mlUrl), {
          method,
          headers: { Accept: 'application/json', ...(method === 'POST' ? { 'Content-Type': 'application/json' } : {}) },
          ...(method === 'POST' ? { body: JSON.stringify(req.body ?? {}) } : {}),
          signal: AbortSignal.timeout(timeoutMs),
        });
        const payload = await upstream.json();
        if (upstream.status === 422) {
          const details = (payload.detail ?? []).map(({ loc, msg, type }) => ({ field: loc, message: msg, type }));
          return res.status(422).json({ error: 'VALIDATION_ERROR', details });
        }
        if (upstream.status === 503) return res.status(503).json({ error: 'MODEL_UNAVAILABLE', message: 'Treine o modelo e reinicie o serviço Python.' });
        if (!upstream.ok) return res.status(502).json({ error: 'ML_ERROR', message: 'Falha no serviço de previsão.' });
        return res.json(payload);
      } catch (error) {
        if (error instanceof SyntaxError) return res.status(502).json({ error: 'ML_ERROR', message: 'Resposta inválida do serviço de previsão.' });
        const timeout = error.name === 'TimeoutError' || error.name === 'AbortError';
        return res.status(timeout ? 504 : 503).json({ error: timeout ? 'ML_TIMEOUT' : 'ML_UNAVAILABLE', message: timeout ? 'Tempo limite do serviço de previsão excedido.' : 'Serviço Python indisponível.' });
      }
    };
  }

  /* ---- Endpoints de saúde e proxy para o serviço ML ---- */

  // Verifica se a API está respondendo.
  app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'logipredict-api', version: '0.2.0' }));

  // Proxies diretos para o serviço ML FastAPI.
  app.get('/ready', proxy('/health'));
  app.get('/api/v1/model', proxy('/model'));
  app.get('/api/v1/analytics/states', proxy('/analytics/states'));

  // Agregação de previsões por hub logístico com deduplicação por order_id.
  // Filtra por período (start_date, end_date) e hub_id opcional.
  app.get('/api/v1/analytics/hubs', async (req, res) => {
    const parseDate = (value) => {
      if (value === undefined) return { value: null };
      if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return { error: true };
      const date = new Date(`${value}T00:00:00.000Z`);
      return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value
        ? { value }
        : { error: true };
    };
    const start = parseDate(req.query.start_date);
    const end = parseDate(req.query.end_date);
    if (start.error || end.error) {
      return res.status(422).json({ error: 'INVALID_DATE', message: 'Use datas válidas no formato YYYY-MM-DD.' });
    }
    if (start.value && end.value && start.value > end.value) {
      return res.status(422).json({ error: 'INVALID_PERIOD', message: 'start_date deve ser anterior ou igual a end_date.' });
    }
    const hubId = req.query.hub_id;
    if (hubId !== undefined && (typeof hubId !== 'string' || !hubId.trim())) {
      return res.status(422).json({ error: 'INVALID_HUB_ID', message: 'hub_id inválido.' });
    }
    try {
      const [history, hubs] = await Promise.all([readPredictions(), readHubs()]);
      const allHubsById = new Map(hubs.map((hub) => [hub.id, hub]));
      if (hubId && !allHubsById.has(hubId)) {
        return res.status(404).json({ error: 'HUB_NOT_FOUND', message: 'O hub informado não existe.' });
      }
      const hubById = new Map(hubs
        .filter((hub) => hub.validationStatus === 'APROVADO')
        .map((hub) => [hub.id, hub]));
      if (hubId && !hubById.has(hubId)) {
        return res.status(409).json({ error: 'HUB_NOT_APPROVED', message: 'Agregações incluem somente hubs aprovados.' });
      }
      const eligible = history.filter((item) => {
        if (!item || typeof item !== 'object' || item.synthetic !== false ||
            typeof item.order_id !== 'string' || !item.order_id ||
            typeof item.hub_id !== 'string' || !hubById.has(item.hub_id) ||
            typeof item.prediction_id !== 'string' || !item.prediction_id ||
            !Number.isFinite(item.delay_probability) || item.delay_probability < 0 || item.delay_probability > 1 ||
            typeof item.predicted_late !== 'boolean' ||
            !Number.isFinite(item.threshold) || item.threshold < 0 || item.threshold > 1 ||
            typeof item.model_version !== 'string' || !item.model_version ||
            typeof item.source !== 'string' || !item.source || !Array.isArray(item.warnings) ||
            item.warnings.some((warning) => typeof warning !== 'string') ||
            typeof item.predicted_at !== 'string' || !Number.isFinite(Date.parse(item.predicted_at))) return false;
        if (hubId && item.hub_id !== hubId) return false;
        const predictionDate = new Date(item.predicted_at).toISOString().slice(0, 10);
        if (start.value && predictionDate < start.value) return false;
        if (end.value && predictionDate > end.value) return false;
        return true;
      });
      // Deduplicate by order_id: keep only the most recent prediction per order.
      // This ensures each order is counted once in hub aggregates, even if the
      // simulation was resumed and re-processed the same order multiple times.
      const byOrder = new Map();
      for (const prediction of eligible) {
        const existing = byOrder.get(prediction.order_id);
        if (!existing || prediction.predicted_at > existing.predicted_at) {
          byOrder.set(prediction.order_id, prediction);
        }
      }
      const deduplicated = [...byOrder.values()];

      const grouped = new Map();
      for (const prediction of deduplicated) {
        if (!grouped.has(prediction.hub_id)) grouped.set(prediction.hub_id, []);
        grouped.get(prediction.hub_id).push(prediction);
      }
      const data = [...grouped.entries()].map(([groupHubId, predictions]) => {
        const thresholds = [...new Set(predictions.map((item) => item.threshold))].sort((a, b) => a - b);
        const modelVersions = [...new Set(predictions.map((item) => item.model_version))].sort();
        const times = predictions.map((item) => item.predicted_at).sort();
        const riskCount = predictions.filter((item) => item.predicted_late).length;
        return {
          hub_id: groupHubId,
          predictions_count: predictions.length,
          risk_count: riskCount,
          risk_percentage: (riskCount / predictions.length) * 100,
          period_start: times[0],
          period_end: times[times.length - 1],
          threshold: thresholds.length === 1 ? thresholds[0] : null,
          thresholds,
          thresholds_consistent: thresholds.length === 1,
          model_version: modelVersions.length === 1 ? modelVersions[0] : null,
          model_versions: modelVersions,
          model_versions_consistent: modelVersions.length === 1,
          last_prediction_at: times[times.length - 1],
        };
      }).sort((a, b) => a.hub_id.localeCompare(b.hub_id));
      return res.json({
        data,
        total: data.length,
        filters: { start_date: start.value, end_date: end.value, hub_id: hubId ?? null },
      });
    } catch (error) {
      console.error('Falha ao agregar histórico de previsões:', error.message);
      return res.status(500).json({ error: 'PREDICTIONS_STORAGE_ERROR', message: 'Não foi possível consultar o histórico de previsões.' });
    }
  });

  /* ---- Importação de dados Olist ---- */

  // Retorna o CSV de pedidos Olist processados para download.
  app.get('/api/v1/datasets/olist', async (_req, res) => {
    try {
      const dataset = await readFile(olistDatasetFile);
      if (dataset.length === 0) {
        return res.status(422).json({ error: 'OLIST_DATASET_EMPTY', message: 'O CSV Olist configurado está vazio.' });
      }
      res.type('text/csv; charset=utf-8');
      res.set('Content-Disposition', 'inline; filename="pedidos_logipredict.csv"');
      return res.send(dataset);
    } catch (error) {
      if (error.code === 'ENOENT') {
        return res.status(404).json({ error: 'OLIST_DATASET_NOT_FOUND', message: 'CSV Olist preparado não encontrado. Configure OLIST_DATASET_FILE na API.' });
      }
      console.error('Falha ao ler CSV Olist configurado:', error.message);
      return res.status(500).json({ error: 'OLIST_DATASET_READ_ERROR', message: 'Não foi possível ler o CSV Olist configurado.' });
    }
  });
  async function callMlPredict(shipment) {
    const upstream = await fetch(new URL('/predict', mlUrl), {
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify(shipment),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const payload = await upstream.json();
    if (upstream.status === 422) {
      const details = (payload.detail ?? []).map(({ loc, msg, type }) => ({ field: loc, message: msg, type }));
      throw { status: 422, error: 'VALIDATION_ERROR', details };
    }
    if (upstream.status === 503) throw { status: 503, error: 'MODEL_UNAVAILABLE', message: 'Treine o modelo e reinicie o serviço Python.' };
    if (!upstream.ok) throw { status: upstream.status, error: 'ML_ERROR', message: 'Falha no serviço de previsão.' };
    return payload;
  }

  /* ---- Previsão de risco de atraso ---- */

  // Prevê o risco de atraso para um pedido individual.
  // Encaminha ao serviço ML FastAPI e armazena no journal (JSONL).
  app.post('/api/v1/predictions', async (req, res) => {
    if (!req.is('application/json')) {
      return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    }
    const hasOrderId = Object.hasOwn(req.query, 'order_id');
    let orderId;
    let capturedHubId = null;
    if (hasOrderId) {
      orderId = normalizeOrderId(req.query.order_id);
      if (!orderId) return res.status(422).json({ error: 'INVALID_ORDER_ID', message: 'Informe um order_id válido.' });
      try {
        const order = (await readOrders()).find((item) => item.order_id === orderId);
        if (!order) return res.status(404).json({ error: 'ORDER_NOT_FOUND', message: 'Importe o pedido antes de registrar uma previsão.' });
        capturedHubId = order.hub_id ?? null;
        if (capturedHubId != null && !(await readHubs()).some((hub) => hub.id === capturedHubId)) {
          return res.status(409).json({ error: 'ORDER_HUB_INVALID', message: 'O hub associado ao pedido não existe mais.' });
        }
      } catch (error) {
        console.error('Falha ao carregar pedido para previsão:', error.message);
        return res.status(500).json({ error: 'ORDER_STORAGE_ERROR', message: 'Não foi possível carregar o pedido para a previsão.' });
      }
    }

    try {
      const payload = await callMlPredict(req.body ?? {});
      if (!hasOrderId) return res.json(payload);

      const probability = payload?.delay_probability;
      const threshold = payload?.threshold;
      if (!Number.isFinite(probability) || probability < 0 || probability > 1 ||
          typeof payload.predicted_late !== 'boolean' ||
          !Number.isFinite(threshold) || threshold < 0 || threshold > 1 ||
          typeof payload.model_version !== 'string' || !payload.model_version ||
          typeof payload.source !== 'string' || !payload.source ||
          typeof payload.synthetic !== 'boolean' || !Array.isArray(payload.warnings)) {
        return res.status(502).json({ error: 'INVALID_ML_RESPONSE', message: 'A resposta do modelo não contém os campos necessários para registrar a previsão.', persisted: false });
      }
      const predictionId = randomUUID();
      const prediction = {
        prediction_id: predictionId,
        order_id: orderId,
        hub_id: capturedHubId,
        delay_probability: probability,
        predicted_late: payload.predicted_late,
        threshold,
        model_version: payload.model_version,
        source: payload.source,
        synthetic: payload.synthetic,
        warnings: payload.warnings,
        predicted_at: new Date().toISOString(),
      };
      try {
        await appendPrediction(prediction);
      } catch (error) {
        console.error('Falha ao gravar histórico de previsões:', error.message);
        return res.status(500).json({
          error: 'PREDICTION_PERSISTENCE_ERROR',
          message: 'O modelo produziu uma previsão, mas ela não foi registrada no histórico.',
          prediction: payload,
          persisted: false,
        });
      }
      return res.json({ ...payload, prediction_id: predictionId, persisted: true });
    } catch (error) {
      if (error instanceof SyntaxError) return res.status(502).json({ error: 'ML_ERROR', message: 'Resposta inválida do serviço de previsão.' });
      if (error.status === 422) return res.status(422).json({ error: error.error, details: error.details });
      if (error.status === 503) return res.status(503).json({ error: error.error, message: error.message });
      const timeout = error.name === 'TimeoutError' || error.name === 'AbortError';
      return res.status(timeout ? 504 : 503).json({ error: timeout ? 'ML_TIMEOUT' : 'ML_UNAVAILABLE', message: timeout ? 'Tempo limite do serviço de previsão excedido.' : 'Serviço Python indisponível.' });
    }
  });

  // Previsão em lote: processa múltiplos pedidos com progresso via Server-Sent Events (SSE).
  // Cada pedido é enviado ao serviço ML e o resultado é armazenado no journal.
  app.post('/api/v1/predictions/batch', async (req, res) => {
    if (!req.is('application/json')) {
      return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    }
    const shipments = req.body?.shipments;
    if (!Array.isArray(shipments) || shipments.length < 1 || shipments.length > 20000) {
      return res.status(422).json({ error: 'INVALID_SHIPMENTS', message: 'Informe de 1 a 20000 pedidos por requisição.' });
    }
    const orderIds = req.body?.orderIds;
    const hasOrders = Array.isArray(orderIds) && orderIds.length === shipments.length;
    if (hasOrders && orderIds.some((id) => typeof id !== 'string' || !id.trim())) {
      return res.status(422).json({ error: 'INVALID_ORDER_ID', message: 'Todos os order_id devem ser strings válidas.' });
    }

    // Load orders map if orderIds are provided
    let ordersMap = null;
    if (hasOrders) {
      try {
        const orders = await readOrders();
        ordersMap = new Map(orders.map((o) => [o.order_id, o]));
      } catch (error) {
        console.error('Falha ao carregar pedidos para batch:', error.message);
        return res.status(500).json({ error: 'ORDER_STORAGE_ERROR', message: 'Não foi possível carregar os pedidos.' });
      }
    }

    // Load existing predictions to skip already-processed orders (idempotency)
    let existingPredictionsByOrder = null;
    if (hasOrders) {
      try {
        const history = await readPredictions();
        existingPredictionsByOrder = new Map();
        for (const pred of history) {
          if (pred && typeof pred === 'object' && typeof pred.order_id === 'string' && pred.order_id) {
            const existing = existingPredictionsByOrder.get(pred.order_id);
            if (!existing || pred.predicted_at > existing.predicted_at) {
              existingPredictionsByOrder.set(pred.order_id, pred);
            }
          }
        }
      } catch (error) {
        console.error('Falha ao carregar previsões existentes para batch:', error.message);
        // Continue without deduplication if journal is unavailable
      }
    }

    // Use SSE for progress streaming
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no',
    });

    const total = shipments.length;
    const startTime = Date.now();
    let succeeded = 0;
    let failed = 0;
    let skipped = 0;

    function sendEvent(data) {
      res.write(`data: ${JSON.stringify(data)}\n\n`);
    }

    sendEvent({ type: 'start', total });

    // Process in chunks sent to client, with limited concurrency within each chunk
    const concurrencyLimit = Math.min(batchConcurrency, shipments.length);
    const processShipment = async (index, shipment, orderId) => {
      // Skip already-processed orders for idempotency
      if (orderId && existingPredictionsByOrder && existingPredictionsByOrder.has(orderId)) {
        skipped++;
        const existing = existingPredictionsByOrder.get(orderId);
        return {
          index,
          orderId,
          prediction: null,
          result: {
            index,
            orderId,
            status: 'skipped',
            message: 'Previsão já existe para este pedido.',
            prediction_id: existing.prediction_id,
            delay_probability: existing.delay_probability,
            predicted_late: existing.predicted_late,
            threshold: existing.threshold,
            model_version: existing.model_version,
          },
        };
      }

      let capturedHubId = null;
      if (orderId && ordersMap) {
        const order = ordersMap.get(orderId);
        if (order) capturedHubId = order.hub_id ?? null;
      }

      try {
        const payload = await callMlPredict(shipment);
        const probability = payload?.delay_probability;
        const threshold = payload?.threshold;

        if (!Number.isFinite(probability) || probability < 0 || probability > 1 ||
            typeof payload.predicted_late !== 'boolean' ||
            !Number.isFinite(threshold) || threshold < 0 || threshold > 1 ||
            typeof payload.model_version !== 'string' || !payload.model_version ||
            typeof payload.source !== 'string' || !payload.source ||
            typeof payload.synthetic !== 'boolean' || !Array.isArray(payload.warnings)) {
          return {
            index,
            orderId,
            error: 'INVALID_ML_RESPONSE',
            message: 'Resposta do modelo inválida.',
          };
        }

        const predictionId = randomUUID();
        const prediction = {
          prediction_id: predictionId,
          order_id: orderId,
          hub_id: capturedHubId,
          delay_probability: probability,
          predicted_late: payload.predicted_late,
          threshold,
          model_version: payload.model_version,
          source: payload.source,
          synthetic: payload.synthetic,
          warnings: payload.warnings,
          predicted_at: new Date().toISOString(),
        };

        return {
          index,
          orderId,
          prediction,
          result: {
            index,
            orderId,
            prediction_id: predictionId,
            delay_probability: probability,
            predicted_late: payload.predicted_late,
            threshold,
            model_version: payload.model_version,
            source: payload.source,
            synthetic: payload.synthetic,
            warnings: payload.warnings,
            persisted: true,
          },
        };
      } catch (error) {
        return {
          index,
          orderId,
          prediction: null,
          result: {
            index,
            orderId,
            error: error.error ?? 'ML_ERROR',
            message: error.message ?? 'Falha na previsão.',
          },
        };
      }
    };

    // Process all shipments with limited concurrency using a worker pool pattern
    const results = new Array(total);
    const predictionsToPersist = [];
    let completed = 0;
    let pending = 0;

    const processNext = async () => {
      while (completed < total) {
        const index = completed;
        completed++;
        pending++;

        const orderId = hasOrders ? orderIds[index] : null;
        const result = await processShipment(index, shipments[index], orderId);

        results[result.index] = result.result;
        if (result.prediction) {
          predictionsToPersist.push(result.prediction);
        }

        pending--;

        // Send progress event and persist when batch is full
        const batchProgress = completed;
        if (completed % batchSize === 0 || completed === total) {
          const batchSucceeded = predictionsToPersist.length;
          const batchFailed = completed - batchSucceeded - (completed - predictionsToPersist.length - results.slice(0, completed).filter((r) => r && r.error).length);

          // Persist predictions for this batch
          if (predictionsToPersist.length > 0) {
            try {
              const dbOk = await checkPredictionsDb();
              if (dbOk) {
                // Salvar no PostgreSQL
                for (const pred of predictionsToPersist) {
                  try {
                    await createPrediction(pred);
                  } catch (e) {
                    console.warn('Falha ao salvar previsão em lote no PostgreSQL:', e.message);
                  }
                }
              } else {
                // Fallback: JSONL
                await serializePredictionMutation(async () => {
                  if (!predictionJournalValidated) {
                    await readPredictions();
                    predictionJournalValidated = true;
                  }
                  await mkdir(path.dirname(predictionJournalFile), { recursive: true });
                  const lines = predictionsToPersist.map((p) => JSON.stringify(p)).join('\n') + '\n';
                  await appendFile(predictionJournalFile, lines, { encoding: 'utf8', mode: 0o600 });
                });
              }
            } catch (error) {
              console.error('Falha ao gravar previsões em lote:', error.message);
            }
            predictionsToPersist.length = 0;
          }

          const elapsed = Date.now() - startTime;
          sendEvent({
            type: 'progress',
            completed: batchProgress,
            total,
            elapsed_ms: elapsed,
          });
        }
      }
    };

    // Run concurrencyLimit workers in parallel
    await Promise.all(
      Array.from({ length: concurrencyLimit }, () => processNext())
    );

    // Final summary
    const finalResults = results.filter((r) => r !== undefined);
    finalResults.sort((a, b) => a.index - b.index);
    succeeded = finalResults.filter((r) => !r.error && r.status !== 'skipped').length;
    failed = finalResults.filter((r) => r.error).length;
    const skippedCount = finalResults.filter((r) => r.status === 'skipped').length;
    const elapsed = Date.now() - startTime;

    sendEvent({
      type: 'complete',
      results: finalResults,
      total,
      succeeded,
      failed,
      skipped: skippedCount,
      elapsed_ms: elapsed,
    });

    res.end();
  });

  /* ---- Geolocalização e cálculo de distância ---- */

  // Inicializa o módulo de geolocalização compartilhado
  const { initGeolocation } = await import('./geolocation.js');
  initGeolocation(geolocationFile);

  // Executar migrations do PostgreSQL automaticamente na inicialização
  try {
    const { getKnex } = await import('./db/knex.js');
    const knex = getKnex();
    await knex.migrate.latest();
    console.log('[DB] Migrations executadas com sucesso.');
  } catch (e) {
    console.warn('[DB] Falha ao executar migrations (usando fallback JSON):', e.message);
  }

  // Expor caminhos de arquivos para rotas modulares (usado pelo fallback JSON)
  app.locals.ordersFile = ordersFile;
  app.locals.hubsFile = hubsFile;
  app.locals.predictionsFile = predictionsFile;
  app.locals.geolocationFile = geolocationFile;

  // Rotas modulares de geolocalização (substitui endpoint inline)
  const geolocationRouter = (await import('./routes/geolocation.js')).default;
  app.use('/api/v1/geolocation', geolocationRouter);

  /* ---- Gerenciamento de pedidos (importação e registro) ---- */

  // Rotas modulares de pedidos (substitui endpoints inline)
  const ordersRouter = (await import('./routes/orders.js')).default;
  app.use('/api/v1/orders', ordersRouter);

  // Rotas modulares de despacho
  const dispatchRouter = (await import('./routes/dispatch.js')).default;
  app.use('/api/v1/dispatch', dispatchRouter);

  /* ---- Gerenciamento de hubs logísticos (CRUD) ---- */

  // Lista todos os hubs com filtro opcional por status.
  app.get('/api/v1/hubs', async (req, res) => {
    try {
      let hubs = await readHubs();
      if (req.query.status !== 'all') hubs = hubs.filter((hub) => hub.status === 'active');
      if (req.query.validationStatus) hubs = hubs.filter((hub) => hub.validationStatus === req.query.validationStatus);
      if (req.query.q) {
        const q = String(req.query.q).trim().toLowerCase();
        hubs = hubs.filter((h) => [h.code, h.name, h.city, h.state, h.operator, h.classification].some((v) => String(v ?? '').toLowerCase().includes(q)));
      }
      return res.json({ data: hubs, total: hubs.length });
    } catch (error) { return handleStorageError(res, error); }
  });

  // Análise de cobertura: quais UFs são atendidas, não atendidas ou compartilhadas.
  // Deve ser definido antes de /:id para que Express não confunda "coverage" com um ID.
  app.get('/api/v1/hubs/coverage', async (req, res) => {
    try {
      const hubs = (await readHubs()).filter((h) => h.validationStatus === 'APROVADO');
      const stateToHubs = new Map();
      for (const hub of hubs) {
        const states = hub.statesServed ?? (hub.state ? [hub.state] : []);
        for (const uf of states) {
          if (!BRAZILIAN_STATES.has(uf)) continue;
          if (!stateToHubs.has(uf)) stateToHubs.set(uf, []);
          stateToHubs.get(uf).push({ id: hub.id, code: hub.code, name: hub.name });
        }
      }
      const allStates = [...BRAZILIAN_STATES].sort();
      const covered = [];
      const uncovered = [];
      const shared = [];
      for (const uf of allStates) {
        const hubList = stateToHubs.get(uf) ?? [];
        if (hubList.length === 0) {
          uncovered.push(uf);
        } else {
          covered.push({ state: uf, hubs: hubList });
          if (hubList.length > 1) {
            shared.push({ state: uf, hub_count: hubList.length, hubs: hubList });
          }
        }
      }
      const hubsWithoutCoverage = hubs
        .filter((h) => !h.statesServed || h.statesServed.length === 0)
        .map((h) => ({ id: h.id, code: h.code, name: h.name, state: h.state }));
      return res.json({
        covered_states: covered,
        uncovered_states: uncovered,
        shared_states: shared,
        hubs_without_coverage: hubsWithoutCoverage,
        total_covered: covered.length,
        total_uncovered: uncovered.length,
      });
    } catch (error) { return handleStorageError(res, error); }
  });

  app.get('/api/v1/hubs/:id', async (req, res) => {
    try {
      const hub = (await readHubs()).find((item) => item.id === req.params.id);
      if (!hub) return res.status(404).json({ error: 'HUB_NOT_FOUND' });
      return res.json({ data: hub });
    } catch (error) { return handleStorageError(res, error); }
  });

  app.post('/api/v1/hubs/import', async (req, res) => {
    if (!req.is('application/json')) return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    if (!Array.isArray(req.body?.candidates) || req.body.candidates.length === 0 || req.body.candidates.length > 2000) {
      return res.status(422).json({ error: 'VALIDATION_ERROR', message: 'Envie uma lista de 1 a 2000 candidatos.' });
    }
    const allowed = new Set(['code', 'name', 'city', 'state', 'validationStatus', 'osmId', 'latitude', 'longitude', 'provisionalCategory', 'osmTags', 'operator', 'owner', 'brand', 'osmUrl', 'classification', 'justification', 'statesServed']);
    const prepared = [];
    for (let i = 0; i < req.body.candidates.length; i++) {
      const candidate = req.body.candidates[i];
      if (!candidate || typeof candidate !== 'object' || Array.isArray(candidate) || Object.keys(candidate).some((key) => !allowed.has(key))) {
        return res.status(422).json({ error: 'VALIDATION_ERROR', message: `Dados inválidos no candidato ${i + 1}.` });
      }
      const { hub, errors } = normalizeHub({ ...candidate, validationStatus: 'PENDENTE_VALIDACAO' });
      if (errors.length) return res.status(422).json({ error: 'VALIDATION_ERROR', details: errors.map((e) => ({ ...e, candidate: i + 1 })) });
      prepared.push(hub);
    }
    try {
      const hubs = await readHubs();
      let added = 0;
      let updated = 0;
      let unchanged = 0;
      const now = new Date().toISOString();
      for (const candidate of prepared) {
        const index = hubs.findIndex((item) => (candidate.osmId && item.osmId === candidate.osmId) || item.code === candidate.code);
        if (index < 0) {
          if (hubs.some((item) => item.code === candidate.code)) {
            return res.status(409).json({ error: 'HUB_CODE_EXISTS', message: `O código ${candidate.code} já pertence a outro hub.` });
          }
          hubs.push({ id: randomUUID(), ...candidate, status: 'inactive', createdAt: now, updatedAt: now });
          added++;
          continue;
        }
        const existing = hubs[index];
        const changed = ['code', 'name', 'city', 'state', 'osmId', 'latitude', 'longitude', 'provisionalCategory', 'osmTags', 'operator', 'owner', 'brand', 'osmUrl', 'classification', 'justification', 'statesServed']
          .some((field) => JSON.stringify(existing[field] ?? null) !== JSON.stringify(candidate[field] ?? null));
        if (!changed) {
          unchanged++;
          continue;
        }
        if (hubs.some((item, i) => i !== index && item.code === candidate.code)) {
          return res.status(409).json({ error: 'HUB_CODE_EXISTS', message: `O código ${candidate.code} já pertence a outro hub.` });
        }
        hubs[index] = { ...existing, ...candidate, status: 'inactive', validationStatus: 'PENDENTE_VALIDACAO', updatedAt: now };
        updated++;
      }
      await writeHubs(hubs);
      return res.json({ added, updated, unchanged, total: prepared.length });
    } catch (error) { return handleStorageError(res, error); }
  });

  app.patch('/api/v1/hubs/bulk/validation', async (req, res) => {
    if (!req.is('application/json')) return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    const ids = req.body?.ids;
    if (!Array.isArray(ids) || ids.length === 0 || ids.length > 2000 || ids.some((id) => typeof id !== 'string' || !id.trim())) {
      return res.status(422).json({ error: 'VALIDATION_ERROR', message: 'Envie uma lista de 1 a 2000 identificadores.' });
    }
    const uniqueIds = [...new Set(ids.map((id) => id.trim()))];
    try {
      const hubs = await readHubs();
      const selected = hubs.filter((hub) => uniqueIds.includes(hub.id));
      const selectedIds = new Set(selected.map((hub) => hub.id));
      if (selected.length !== uniqueIds.length) {
        return res.status(404).json({ error: 'HUB_NOT_FOUND', missingIds: uniqueIds.filter((id) => !selectedIds.has(id)) });
      }
      const pendingWithoutCity = selected.filter((hub) =>
        hub.validationStatus === 'PENDENTE_VALIDACAO' && String(hub.city ?? '').trim().length < 2,
      );
      if (pendingWithoutCity.length) {
        return res.status(422).json({
          error: 'VALIDATION_ERROR',
          details: pendingWithoutCity.map((hub) => ({ id: hub.id, field: 'city', message: `Informe a cidade para aprovar ${hub.name}.` })),
        });
      }
      let added = 0;
      const now = new Date().toISOString();
      const selectedIdSet = new Set(uniqueIds);
      const updated = hubs.map((hub) => {
        if (!selectedIdSet.has(hub.id) || hub.validationStatus !== 'PENDENTE_VALIDACAO') return hub;
        added++;
        return { ...hub, validationStatus: 'APROVADO', status: 'active', updatedAt: now };
      });
      if (added) await writeHubs(updated);
      return res.json({ added, skipped: uniqueIds.length - added, total: uniqueIds.length });
    } catch (error) { return handleStorageError(res, error); }
  });

  app.post('/api/v1/hubs', async (req, res) => {
    if (!req.is('application/json')) return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body)) return res.status(400).json({ error: 'INVALID_BODY' });
    const allowed = new Set(['code', 'name', 'city', 'state', 'validationStatus', 'osmId', 'latitude', 'longitude', 'provisionalCategory', 'osmTags', 'operator', 'owner', 'brand', 'osmUrl', 'classification', 'justification', 'statesServed']);
    const unknown = Object.keys(req.body).filter((key) => !allowed.has(key));
    if (unknown.length) return res.status(400).json({ error: 'UNKNOWN_FIELDS', fields: unknown });
    const { hub, errors } = normalizeHub(req.body);
    if (errors.length) return res.status(422).json({ error: 'VALIDATION_ERROR', details: errors });
    try {
      const hubs = await readHubs();
      if (hubs.some((item) => item.code === hub.code)) return res.status(409).json({ error: 'HUB_CODE_EXISTS', message: 'Já existe um hub com esse código.' });
      const now = new Date().toISOString();
      const created = { id: randomUUID(), ...hub, status: hub.validationStatus === 'APROVADO' ? 'active' : 'inactive', createdAt: now, updatedAt: now };
      hubs.push(created);
      await writeHubs(hubs);
      return res.status(201).json({ data: created });
    } catch (error) { return handleStorageError(res, error); }
  });

  app.put('/api/v1/hubs/:id', async (req, res) => {
    if (!req.is('application/json')) return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    if (!req.body || typeof req.body !== 'object' || Array.isArray(req.body)) return res.status(400).json({ error: 'INVALID_BODY' });
    const allowed = new Set(['code', 'name', 'city', 'state', 'validationStatus', 'osmId', 'latitude', 'longitude', 'provisionalCategory', 'osmTags', 'operator', 'owner', 'brand', 'osmUrl', 'classification', 'justification', 'statesServed']);
    const unknown = Object.keys(req.body).filter((key) => !allowed.has(key));
    if (unknown.length) return res.status(400).json({ error: 'UNKNOWN_FIELDS', fields: unknown });
    try {
      const hubs = await readHubs();
      const index = hubs.findIndex((item) => item.id === req.params.id);
      if (index < 0) return res.status(404).json({ error: 'HUB_NOT_FOUND' });
      const { hub, errors } = normalizeHub(req.body, hubs[index]);
      if (errors.length) return res.status(422).json({ error: 'VALIDATION_ERROR', details: errors });
      if (hubs.some((item, i) => i !== index && item.code === hub.code)) return res.status(409).json({ error: 'HUB_CODE_EXISTS', message: 'Já existe um hub com esse código.' });
      hubs[index] = { ...hubs[index], ...hub, updatedAt: new Date().toISOString() };
      await writeHubs(hubs);
      return res.json({ data: hubs[index] });
    } catch (error) { return handleStorageError(res, error); }
  });

  app.patch('/api/v1/hubs/:id/status', async (req, res) => {
    if (!req.is('application/json')) return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    if (typeof req.body?.active !== 'boolean') return res.status(422).json({ error: 'VALIDATION_ERROR', details: [{ field: 'active', message: 'Informe true ou false.' }] });
    try {
      const hubs = await readHubs();
      const index = hubs.findIndex((item) => item.id === req.params.id);
      if (index < 0) return res.status(404).json({ error: 'HUB_NOT_FOUND' });
      if (req.body.active && hubs[index].validationStatus !== 'APROVADO') {
        return res.status(409).json({ error: 'HUB_NOT_APPROVED', message: 'Valide o candidato antes de ativar o hub.' });
      }
      hubs[index] = { ...hubs[index], status: req.body.active ? 'active' : 'inactive', updatedAt: new Date().toISOString() };
      await writeHubs(hubs);
      return res.json({ data: hubs[index] });
    } catch (error) { return handleStorageError(res, error); }
  });

  app.patch('/api/v1/hubs/:id/validation', async (req, res) => {
    if (!req.is('application/json')) return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    const validationStatus = req.body?.validationStatus;
    if (!['PENDENTE_VALIDACAO', 'APROVADO', 'REJEITADO'].includes(validationStatus)) {
      return res.status(422).json({ error: 'VALIDATION_ERROR', details: [{ field: 'validationStatus', message: 'Estado de validação inválido.' }] });
    }
    try {
      const hubs = await readHubs();
      const index = hubs.findIndex((item) => item.id === req.params.id);
      if (index < 0) return res.status(404).json({ error: 'HUB_NOT_FOUND' });
      if (validationStatus === 'APROVADO' && hubs[index].city.trim().length < 2) {
        return res.status(422).json({ error: 'VALIDATION_ERROR', details: [{ field: 'city', message: 'Informe a cidade antes de aprovar o hub.' }] });
      }
      hubs[index] = {
        ...hubs[index],
        validationStatus,
        status: validationStatus === 'APROVADO' ? 'active' : 'inactive',
        updatedAt: new Date().toISOString(),
      };
      await writeHubs(hubs);
      return res.json({ data: hubs[index] });
    } catch (error) { return handleStorageError(res, error); }
  });

  app.delete('/api/v1/hubs/bulk', async (req, res) => {
    if (!req.is('application/json')) return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    const ids = req.body?.ids;
    if (!Array.isArray(ids) || ids.length === 0 || ids.length > 2000 || ids.some((id) => typeof id !== 'string' || !id.trim())) {
      return res.status(422).json({ error: 'VALIDATION_ERROR', message: 'Envie uma lista de 1 a 2000 identificadores.' });
    }
    const uniqueIds = [...new Set(ids.map((id) => id.trim()))];
    try {
      const hubs = await readHubs();
      const found = hubs.filter((hub) => uniqueIds.includes(hub.id));
      const foundIds = new Set(found.map((hub) => hub.id));
      if (found.length !== uniqueIds.length) {
        return res.status(404).json({ error: 'HUB_NOT_FOUND', missingIds: uniqueIds.filter((id) => !foundIds.has(id)) });
      }
      const usedHubs = [...new Set((await readOrders())
        .filter((order) => foundIds.has(order.hub_id))
        .map((order) => order.hub_id))];
      if (usedHubs.length) {
        return res.status(409).json({
          error: 'HUB_IN_USE',
          message: 'Não é possível excluir hubs associados a pedidos. Remova ou altere os vínculos primeiro.',
          hubIds: usedHubs,
        });
      }
      const remaining = hubs.filter((hub) => !foundIds.has(hub.id));
      await writeHubs(remaining);
      return res.json({ deleted: found.length, ids: uniqueIds });
    } catch (error) { return handleStorageError(res, error); }
  });

  // Update states served coverage for a specific hub.
  app.patch('/api/v1/hubs/:id/states-served', async (req, res) => {
    if (!req.is('application/json')) return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    if (req.body?.statesServed === undefined) {
      return res.status(422).json({ error: 'VALIDATION_ERROR', details: [{ field: 'statesServed', message: 'Informe statesServed.' }] });
    }
    try {
      const hubs = await readHubs();
      const index = hubs.findIndex((item) => item.id === req.params.id);
      if (index < 0) return res.status(404).json({ error: 'HUB_NOT_FOUND' });
      const { statesServed, errors } = normalizeStatesServed(req.body.statesServed, hubs[index].statesServed);
      if (errors.length) return res.status(422).json({ error: 'VALIDATION_ERROR', details: errors });
      hubs[index] = { ...hubs[index], statesServed, updatedAt: new Date().toISOString() };
      await writeHubs(hubs);
      return res.json({ data: hubs[index] });
    } catch (error) { return handleStorageError(res, error); }
  });

  app.delete('/api/v1/hubs/:id', async (req, res) => {
    try {
      const hubs = await readHubs();
      const index = hubs.findIndex((item) => item.id === req.params.id);
      if (index < 0) return res.status(404).json({ error: 'HUB_NOT_FOUND' });
      const used = (await readOrders()).some((order) => order.hub_id === req.params.id);
      if (used) {
        return res.status(409).json({
          error: 'HUB_IN_USE',
          message: 'Não é possível excluir um hub associado a pedidos. Remova ou altere os vínculos primeiro.',
        });
      }
      hubs.splice(index, 1);
      await writeHubs(hubs);
      return res.status(204).end();
    } catch (error) { return handleStorageError(res, error); }
  });

  /* ---- Alocação automática de hubs por estado ---- */

  // Aloca hubs a pedidos com base no estado do cliente.
  // Usa hash determinístico do order_id para balancear entre hubs elegíveis.
  // É uma simulação demonstrativa e não reflete a logística real da Olist.
  app.post('/api/v1/orders/assign-hubs-by-state', async (req, res) => {
    if (!req.is('application/json')) {
      return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    }
    const orders = req.body?.orders;
    if (!Array.isArray(orders) || orders.length < 1 || orders.length > 2000) {
      return res.status(422).json({ error: 'INVALID_ORDERS', message: 'Informe de 1 a 2000 pedidos.' });
    }
    const dryRun = req.body?.dry_run === true;
    const states = new Set(['AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO']);

    // Validate input
    const prepared = [];
    for (let i = 0; i < orders.length; i++) {
      const entry = orders[i];
      if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
        return res.status(422).json({ error: 'INVALID_ORDER', message: `Dados inválidos no pedido ${i + 1}.` });
      }
      const orderId = normalizeOrderId(entry?.order_id);
      if (!orderId) {
        return res.status(422).json({ error: 'INVALID_ORDER_ID', message: `order_id inválido no pedido ${i + 1}.` });
      }
      const customerState = typeof entry?.customer_state === 'string'
        ? entry.customer_state.trim().toUpperCase()
        : '';
      if (!states.has(customerState)) {
        return res.status(422).json({ error: 'INVALID_STATE', message: `customer_state inválido no pedido ${i + 1}: "${entry?.customer_state}". Use uma UF brasileira.` });
      }
      prepared.push({ orderId, customerState });
    }

    // Simple deterministic hash for distributing orders among hubs of the same state.
    function simpleHash(str) {
      let hash = 0;
      for (let i = 0; i < str.length; i++) {
        const ch = str.charCodeAt(i);
        hash = ((hash << 5) - hash + ch) | 0;
      }
      return Math.abs(hash);
    }

    try {
      const [hubs, existingOrders, predictions] = await Promise.all([
        readHubs(),
        readOrders(),
        readPredictions(),
      ]);

      // Build hub index: state -> array of approved hub ids
      // Use statesServed if configured; fall back to hub.state for legacy hubs.
      const hubsByState = new Map();
      for (const hub of hubs) {
        if (hub.validationStatus !== 'APROVADO') continue;
        let states = hub.statesServed;
        if (!states || states.length === 0) {
          // Legacy hub without explicit coverage — fall back to its own state
          states = hub.state ? [hub.state] : [];
        }
        for (const uf of states) {
          if (!BRAZILIAN_STATES.has(uf)) continue;
          if (!hubsByState.has(uf)) hubsByState.set(uf, []);
          hubsByState.get(uf).push(hub.id);
        }
      }

      // Sort hub ids per state for deterministic ordering
      for (const [, ids] of hubsByState) ids.sort();

      // Build order index
      const orderIndex = new Map(existingOrders.map((o, idx) => [o.order_id, idx]));

      // Build set of order_ids that already have predictions
      const ordersWithPredictions = new Set();
      for (const pred of predictions) {
        if (typeof pred?.order_id === 'string' && pred.order_id.trim()) {
          ordersWithPredictions.add(pred.order_id.trim());
        }
      }

      // Calculate assignments
      const assignments = [];
      const stateHubCount = new Map();
      const stateNoHubCount = new Map();
      const stateOrderCount = new Map(); // total orders per destination state
      const hubOrderCount = new Map(); // total orders per assigned hub
      const reasonCount = new Map(); // count per reason code
      let totalAnalyzed = 0;
      let totalUnassigned = 0;
      let totalWouldChange = 0;
      let totalWithPrediction = 0;
      let totalWithoutOrder = 0;

      for (const { orderId, customerState } of prepared) {
        totalAnalyzed++;
        // Count orders per destination state
        stateOrderCount.set(customerState, (stateOrderCount.get(customerState) || 0) + 1);
        const eligibleHubs = hubsByState.get(customerState);
        const orderIdx = orderIndex.get(orderId);

        if (!eligibleHubs || eligibleHubs.length === 0) {
          // No hub for this state
          totalUnassigned++;
          stateNoHubCount.set(customerState, (stateNoHubCount.get(customerState) || 0) + 1);
          const reason = 'NO_HUB_FOR_STATE';
          reasonCount.set(reason, (reasonCount.get(reason) || 0) + 1);
          assignments.push({
            order_id: orderId,
            customer_state: customerState,
            assigned_hub_id: null,
            reason,
            has_prediction: ordersWithPredictions.has(orderId),
            exists_in_orders: orderIdx !== undefined,
          });
          continue;
        }

        // Deterministic selection: hash(order_id) % num_eligible_hubs
        const hash = simpleHash(orderId);
        const selectedHubId = eligibleHubs[hash % eligibleHubs.length];

        // Track count per state/hub
        const key = `${customerState}/${selectedHubId}`;
        stateHubCount.set(key, (stateHubCount.get(key) || 0) + 1);
        // Track count per hub
        hubOrderCount.set(selectedHubId, (hubOrderCount.get(selectedHubId) || 0) + 1);

        const hasPrediction = ordersWithPredictions.has(orderId);
        if (hasPrediction) totalWithPrediction++;

        const existsInOrders = orderIdx !== undefined;
        if (!existsInOrders) totalWithoutOrder++;

        const currentHubId = existsInOrders ? existingOrders[orderIdx]?.hub_id : null;
        const wouldChange = currentHubId !== selectedHubId;
        if (wouldChange) totalWouldChange++;

        const reason = hasPrediction ? 'HAS_PREDICTION' : (wouldChange ? 'WOULD_CHANGE' : 'UNCHANGED');
        reasonCount.set(reason, (reasonCount.get(reason) || 0) + 1);
        assignments.push({
          order_id: orderId,
          customer_state: customerState,
          assigned_hub_id: selectedHubId,
          reason,
          has_prediction: hasPrediction,
          exists_in_orders: existsInOrders,
          current_hub_id: currentHubId,
        });
      }

      // Build summary by state/hub
      const distribution = [];
      for (const [key, count] of [...stateHubCount.entries()].sort()) {
        const [state, hubId] = key.split('/');
        const hub = hubs.find((h) => h.id === hubId);
        distribution.push({
          state,
          hub_id: hubId,
          hub_code: hub?.code ?? null,
          hub_name: hub?.name ?? null,
          orders_count: count,
        });
      }

      // States without hub coverage
      const uncoveredStates = [...stateNoHubCount.entries()]
        .map(([state, count]) => ({ state, orders_count: count }))
        .sort((a, b) => b.orders_count - a.orders_count);

      // Orders count per destination state
      const stateCounts = [...stateOrderCount.entries()]
        .map(([state, count]) => ({ state, orders_count: count }))
        .sort((a, b) => b.orders_count - a.orders_count);

      // Orders count per assigned hub
      const hubCounts = [...hubOrderCount.entries()]
        .map(([hubId, count]) => {
          const hub = hubs.find((h) => h.id === hubId);
          return {
            hub_id: hubId,
            hub_code: hub?.code ?? null,
            hub_name: hub?.name ?? null,
            orders_count: count,
            percentage: totalAnalyzed > 0 ? (count / totalAnalyzed * 100) : 0,
          };
        })
        .sort((a, b) => b.orders_count - a.orders_count);

      // Reason breakdown
      const reasons = [...reasonCount.entries()]
        .map(([reason, count]) => ({ reason, count }))
        .sort((a, b) => b.count - a.count);

      if (dryRun) {
        return res.json({
          dry_run: true,
          summary: {
            total_analyzed: totalAnalyzed,
            total_would_change: totalWouldChange,
            total_unassigned: totalUnassigned,
            total_with_prediction: ordersWithPredictions.size > 0 ? totalWithPrediction : 0,
            total_without_order: totalWithoutOrder,
            states_covered: hubsByState.size,
            states_uncovered: uncoveredStates.length,
          },
          state_counts: stateCounts,
          hub_counts: hubCounts,
          reasons,
          distribution,
          uncovered_states: uncoveredStates,
          assignments: assignments.slice(0, 100), // Limit preview
          assignments_total: assignments.length,
        });
      }

      // Apply assignments
      const now = new Date().toISOString();
      let assigned = 0;
      let unchanged = 0;
      let skipped = 0;

      for (const assignment of assignments) {
        if (assignment.assigned_hub_id === null) {
          skipped++;
          continue;
        }
        const orderIdx = orderIndex.get(assignment.order_id);
        if (orderIdx === undefined) {
          // Order not in orders.json yet — skip, user should import first
          skipped++;
          continue;
        }
        const currentOrder = existingOrders[orderIdx];
        if (currentOrder.hub_id === assignment.assigned_hub_id) {
          unchanged++;
          continue;
        }
        existingOrders[orderIdx] = {
          ...currentOrder,
          hub_id: assignment.assigned_hub_id,
          updatedAt: now,
        };
        assigned++;
      }

      if (assigned > 0) {
        await writeOrders(existingOrders);
      }

      return res.json({
        dry_run: false,
        summary: {
          total_analyzed: totalAnalyzed,
          assigned: assigned,
          unchanged: unchanged,
          skipped: skipped,
          total_unassigned: totalUnassigned,
          total_with_prediction: totalWithPrediction,
        },
        state_counts: stateCounts,
        hub_counts: hubCounts,
        reasons,
        distribution,
        uncovered_states: uncoveredStates,
      });
    } catch (error) {
      console.error('Falha ao atribuir hubs por estado:', error.message);
      return res.status(500).json({ error: 'ORDER_STORAGE_ERROR', message: 'Não foi possível processar a atribuição de hubs.' });
    }
  });

  /* ---- Limpeza administrativa de pedidos ---- */

  // Remove pedidos e previsões associadas por fonte (source).
  // Exige confirmação explícita; suporta dry-run para prévia segura.
  app.delete('/api/v1/orders/cleanup', async (req, res) => {
    if (!req.is('application/json')) {
      return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    }
    const body = req.body;
    if (!body || typeof body !== 'object') {
      return res.status(422).json({ error: 'INVALID_BODY', message: 'Corpo da requisição inválido.' });
    }

    const rawSource = body?.source;
    const source = typeof rawSource === 'string' ? rawSource.trim().toLowerCase() : '';
    if (!source) {
      return res.status(422).json({ error: 'MISSING_SOURCE', message: 'Informe o source dos pedidos a remover (ex.: "olist").' });
    }

    const dryRun = body?.dry_run === true;
    const confirm = body?.confirm === true;

    if (!dryRun && !confirm) {
      return res.status(422).json({
        error: 'CONFIRMATION_REQUIRED',
        message: 'Para executar a limpeza, envie {"source": "...", "confirm": true}. Use "dry_run": true para uma prévia.',
      });
    }

    try {
      const [orders, predictions] = await Promise.all([readOrders(), readPredictions()]);

      // Find orders matching the source
      const matchingOrderIds = new Set();
      for (const order of orders) {
        if ((order.source ?? '').toLowerCase() === source) {
          matchingOrderIds.add(order.order_id);
        }
      }

      // Count predictions for matching orders
      let matchingPredictions = 0;
      let nonMatchingPredictions = 0;
      for (const pred of predictions) {
        if (matchingOrderIds.has(pred.order_id)) {
          matchingPredictions++;
        } else {
          nonMatchingPredictions++;
        }
      }

      const summary = {
        source,
        orders_to_remove: matchingOrderIds.size,
        total_orders: orders.length,
        orders_preserved: orders.length - matchingOrderIds.size,
        predictions_to_remove: matchingPredictions,
        total_predictions: predictions.length,
        predictions_preserved: nonMatchingPredictions,
      };

      if (dryRun) {
        return res.json({
          dry_run: true,
          summary,
          message: 'Esta é uma prévia. Envie "confirm": true para executar a limpeza.',
        });
      }

      // Execute cleanup
      const remainingOrders = orders.filter((o) => !matchingOrderIds.has(o.order_id));
      await writeOrders(remainingOrders);

      // Rebuild predictions.jsonl keeping only non-matching predictions
      if (matchingPredictions > 0) {
        const remainingPredictions = predictions.filter((p) => !matchingOrderIds.has(p.order_id));
        await serializePredictionMutation(async () => {
          await mkdir(path.dirname(predictionJournalFile), { recursive: true });
          if (remainingPredictions.length > 0) {
            const content = remainingPredictions.map((p) => JSON.stringify(p)).join('\n') + '\n';
            await writeFile(predictionJournalFile, content, { encoding: 'utf8', mode: 0o600 });
          } else {
            // Empty the journal
            await writeFile(predictionJournalFile, '', { encoding: 'utf8', mode: 0o600 });
          }
        });
      }

      // Also update predictions.json if it exists
      try {
        const predJsonContent = await readFile(predictionsFile, 'utf8');
        const predJson = JSON.parse(predJsonContent);
        if (Array.isArray(predJson)) {
          const remainingPredJson = predJson.filter((p) => !matchingOrderIds.has(p.order_id));
          if (remainingPredJson.length !== predJson.length) {
            await serializePredictionMutation(async () => {
              await writeFile(predictionsFile, JSON.stringify(remainingPredJson, null, 2) + '\n', { encoding: 'utf8', mode: 0o600 });
            });
          }
        }
      } catch {
        // predictions.json may not exist; ignore
      }

      console.log(`Cleanup completed: source="${source}", removed ${matchingOrderIds.size} orders and ${matchingPredictions} predictions.`);

      return res.json({
        dry_run: false,
        summary,
        message: `Limpeza concluída: ${matchingOrderIds.size} pedidos e ${matchingPredictions} previsões removidos.`,
      });
    } catch (error) {
      console.error('Falha na limpeza de pedidos:', error.message);
      return res.status(500).json({ error: 'CLEANUP_ERROR', message: 'Não foi possível executar a limpeza.' });
    }
  });

  /* ---- Brazilian region mapping ---- */
  const STATE_TO_REGION = {
    AC: 'Norte', AM: 'Norte', AP: 'Norte', PA: 'Norte', RO: 'Norte', RR: 'Norte', TO: 'Norte',
    AL: 'Nordeste', BA: 'Nordeste', CE: 'Nordeste', MA: 'Nordeste', PB: 'Nordeste', PE: 'Nordeste', PI: 'Nordeste', RN: 'Nordeste', SE: 'Nordeste',
    DF: 'Centro-Oeste', GO: 'Centro-Oeste', MS: 'Centro-Oeste', MT: 'Centro-Oeste',
    ES: 'Sudeste', MG: 'Sudeste', RJ: 'Sudeste', SP: 'Sudeste',
    PR: 'Sul', RS: 'Sul', SC: 'Sul',
  };

  /* ---- Análise geográfica de pedidos ---- */

  // Retorna estatísticas de pedidos por UF: total, atrasados, taxa e classificação de risco.
  // Suporta filtro por estado específico.
  app.get('/api/v1/analytics/orders-geography', async (req, res) => {
    try {
      const stateFilter = typeof req.query.state === 'string'
        ? req.query.state.trim().toUpperCase()
        : null;

      const [orders, customers, geolocation] = await Promise.all([
        loadOrdersDataset(),
        loadCustomersDataset(),
        getGeolocationIndex(),
      ]);

      // Build a set of seen order IDs to avoid duplication
      const seenOrderIds = new Set();

      // Aggregate by (city, state)
      const aggregation = new Map();
      for (const order of orders) {
        if (!order.order_id || seenOrderIds.has(order.order_id)) continue;
        seenOrderIds.add(order.order_id);

        const customer = customers.get(order.customer_id);
        if (!customer || !customer.zip_code_prefix) continue;

        const geo = geolocation.get(customer.zip_code_prefix);
        if (!geo || !Number.isFinite(geo.latitude) || !Number.isFinite(geo.longitude)) continue;

        const city = customer.city || geo.city;
        const state = customer.state || geo.state;
        if (!city || !state) continue;

        if (stateFilter && state !== stateFilter) continue;

        const key = `${city}|||${state}`;
        let bucket = aggregation.get(key);
        if (!bucket) {
          bucket = {
            city,
            state,
            total_orders: 0,
            orders_with_valid_dates: 0,
            delayed_orders: 0,
            orders_without_delivery_date: 0,
            latitude: geo.latitude,
            longitude: geo.longitude,
          };
          aggregation.set(key, bucket);
        }
        bucket.total_orders++;

        // Parse dates — compare calendar dates only (date part)
        const delivered = order.delivered_date ? order.delivered_date.slice(0, 10) : null;
        const estimated = order.estimated_date ? order.estimated_date.slice(0, 10) : null;

        if (!delivered) {
          bucket.orders_without_delivery_date++;
          continue;
        }

        // Order has a delivery date; check if estimated date is also present
        if (!estimated) {
          // No estimated date — can't determine delay, count as valid but not delayed
          bucket.orders_with_valid_dates++;
          continue;
        }

        bucket.orders_with_valid_dates++;
        if (delivered > estimated) {
          bucket.delayed_orders++;
        }
      }

      // Build response
      const data = [];
      for (const bucket of aggregation.values()) {
        const delayRate =
          bucket.orders_with_valid_dates > 0
            ? Math.round((bucket.delayed_orders / bucket.orders_with_valid_dates) * 10000) / 100
            : 0;
        const riskLevel = classifyOrderRisk(bucket.orders_with_valid_dates, bucket.delayed_orders);
        data.push({
          city: bucket.city,
          state: bucket.state,
          total_orders: bucket.total_orders,
          orders_with_valid_dates: bucket.orders_with_valid_dates,
          delayed_orders: bucket.delayed_orders,
          orders_without_delivery_date: bucket.orders_without_delivery_date,
          delay_rate: delayRate,
          risk_level: riskLevel,
          latitude: Math.round(bucket.latitude * 10000) / 10000,
          longitude: Math.round(bucket.longitude * 10000) / 10000,
        });
      }

      return res.json({
        data,
        total: data.length,
        filters: { state: stateFilter },
      });
    } catch (error) {
      console.error('Falha ao agregar geografia de pedidos:', error.message);
      return res.status(500).json({
        error: 'ORDERS_GEOGRAPHY_ERROR',
        message: 'Não foi possível calcular a geografia de pedidos.',
      });
    }
  });

  // Retorna agregação por região brasileira (Norte, Nordeste, Centro-Oeste, Sudeste, Sul).
  // Agrupa os dados por UF e mapeia para as 5 regiões oficiais.
  app.get('/api/v1/analytics/orders-geography/regions', async (req, res) => {
    try {
      const [orders, customers] = await Promise.all([
        loadOrdersDataset(),
        loadCustomersDataset(),
      ]);

      // Build a set of seen order IDs to avoid duplication
      const seenOrderIds = new Set();

      // Aggregate by region, and also track per-state breakdown
      const regionAgg = new Map();
      for (const order of orders) {
        if (!order.order_id || seenOrderIds.has(order.order_id)) continue;
        seenOrderIds.add(order.order_id);

        const customer = customers.get(order.customer_id);
        if (!customer || !customer.state) continue;

        const state = customer.state.toUpperCase();
        const region = STATE_TO_REGION[state];
        if (!region) continue;

        let rBucket = regionAgg.get(region);
        if (!rBucket) {
          rBucket = {
            region,
            total_orders: 0,
            orders_with_valid_dates: 0,
            delayed_orders: 0,
            orders_without_delivery_date: 0,
            states: new Map(),
          };
          regionAgg.set(region, rBucket);
        }
        rBucket.total_orders++;

        // Per-state tracking
        let sBucket = rBucket.states.get(state);
        if (!sBucket) {
          sBucket = {
            state,
            total_orders: 0,
            orders_with_valid_dates: 0,
            delayed_orders: 0,
            orders_without_delivery_date: 0,
          };
          rBucket.states.set(state, sBucket);
        }
        sBucket.total_orders++;

        // Parse dates
        const delivered = order.delivered_date ? order.delivered_date.slice(0, 10) : null;
        const estimated = order.estimated_date ? order.estimated_date.slice(0, 10) : null;

        if (!delivered) {
          rBucket.orders_without_delivery_date++;
          sBucket.orders_without_delivery_date++;
          continue;
        }

        if (!estimated) {
          rBucket.orders_with_valid_dates++;
          sBucket.orders_with_valid_dates++;
          continue;
        }

        rBucket.orders_with_valid_dates++;
        sBucket.orders_with_valid_dates++;
        if (delivered > estimated) {
          rBucket.delayed_orders++;
          sBucket.delayed_orders++;
        }
      }

      // Build response — always return all 5 regions, even if empty
      const allRegions = ['Norte', 'Nordeste', 'Centro-Oeste', 'Sudeste', 'Sul'];
      const data = [];
      for (const regionName of allRegions) {
        const rBucket = regionAgg.get(regionName);
        if (!rBucket) {
          data.push({
            region: regionName,
            total_orders: 0,
            orders_with_valid_dates: 0,
            delayed_orders: 0,
            orders_without_delivery_date: 0,
            delay_rate: 0,
            risk_level: 'sem_dados',
            states: [],
          });
          continue;
        }

        const delayRate =
          rBucket.orders_with_valid_dates > 0
            ? Math.round((rBucket.delayed_orders / rBucket.orders_with_valid_dates) * 10000) / 100
            : 0;
        const riskLevel = classifyOrderRisk(rBucket.orders_with_valid_dates, rBucket.delayed_orders);

        // Build state breakdown sorted by delay rate desc
        const states = [];
        for (const sBucket of rBucket.states.values()) {
          const sRate =
            sBucket.orders_with_valid_dates > 0
              ? Math.round((sBucket.delayed_orders / sBucket.orders_with_valid_dates) * 10000) / 100
              : 0;
          const sRisk = classifyOrderRisk(sBucket.orders_with_valid_dates, sBucket.delayed_orders);
          states.push({
            state: sBucket.state,
            total_orders: sBucket.total_orders,
            orders_with_valid_dates: sBucket.orders_with_valid_dates,
            delayed_orders: sBucket.delayed_orders,
            orders_without_delivery_date: sBucket.orders_without_delivery_date,
            delay_rate: sRate,
            risk_level: sRisk,
          });
        }
        states.sort((a, b) => b.delay_rate - a.delay_rate);

        data.push({
          region: regionName,
          total_orders: rBucket.total_orders,
          orders_with_valid_dates: rBucket.orders_with_valid_dates,
          delayed_orders: rBucket.delayed_orders,
          orders_without_delivery_date: rBucket.orders_without_delivery_date,
          delay_rate: delayRate,
          risk_level: riskLevel,
          states,
        });
      }

      return res.json({ data, total: data.length });
    } catch (error) {
      console.error('Falha ao agregar regiões de pedidos:', error.message);
      return res.status(500).json({
        error: 'ORDERS_REGION_ERROR',
        message: 'Não foi possível calcular a agregação por região.',
      });
    }
  });

  app.use((_req, res) => res.status(404).json({ error: 'NOT_FOUND' }));
  app.use((error, _req, res, _next) => {
    if (error.type === 'entity.too.large') return res.status(413).json({ error: 'PAYLOAD_TOO_LARGE' });
    if (error.type === 'entity.parse.failed') return res.status(400).json({ error: 'INVALID_JSON' });
    return res.status(500).json({ error: 'INTERNAL_ERROR' });
  });
  return app;
}
