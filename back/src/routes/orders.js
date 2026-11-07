/**
 * Rotas de pedidos operacionais.
 *
 * Substitui o endpoint orders/import original (apenas order_id + hub_id)
 * por um endpoint que aceita CSV completo com todos os campos do contrato ML
 * mais campos operacionais (CEPs).
 */
import express from 'express';
import path from 'node:path';
import { normalizeCep, normalizeOrderId, parseCsvRecord, BRAZILIAN_STATES } from '../utils.js';
import { create as createOrder, findById as findOrderById, list as listOrders, updateHub as updateOrderHub, associateHub, checkDb as checkOrdersDb, summary as ordersSummary } from '../db/repositories/orders.js';
import { listActive as listActiveHubs, findById as findHubById } from '../db/repositories/hubs.js';
import { getGeolocationIndex } from '../geolocation.js';
import { haversineKm } from '../utils.js';

const router = express.Router();

// Colunas obrigatórias no CSV operacional
const REQUIRED_COLUMNS = [
  'order_id',
  'origin_zip_code',
  'destination_zip_code',
  'purchase_at',
  'dispatched_at',
  'estimated_delivery_at',
  'seller_state',
  'customer_state',
  'items_count',
  'sellers_count',
  'price',
  'freight_value',
];

/**
 * Valida um valor numérico não negativo.
 */
function parseNonNegativeFloat(value, fieldName) {
  const num = parseFloat(value.replace(',', '.'));
  if (!Number.isFinite(num) || num < 0) {
    return { error: `Valor inválido em ${fieldName}: ${value}` };
  }
  return { value: num };
}

/**
 * Valida um inteiro positivo.
 */
function parsePositiveInt(value, fieldName) {
  const num = parseInt(value, 10);
  if (!Number.isFinite(num) || num < 1) {
    return { error: `Valor inválido em ${fieldName}: ${value}` };
  }
  return { value: num };
}

/**
 * Valida uma data ISO.
 */
function parseDate(value, fieldName) {
  const parsed = new Date(value);
  if (isNaN(parsed.getTime())) {
    return { error: `Data inválida em ${fieldName}: ${value}` };
  }
  return { value: value };
}

/**
 * Lê ou inicializa o arquivo orders.json.
 */
async function readOrdersJson(req) {
  const { readFile } = await import('node:fs/promises');
  const ordersFile = (req.app && req.app.locals && req.app.locals.ordersFile)
    || process.env.ORDERS_FILE
    || path.resolve(process.cwd(), 'data', 'orders.json');
  try {
    const content = await readFile(ordersFile, 'utf8');
    const parsed = JSON.parse(content);
    if (!Array.isArray(parsed)) return [];
    return parsed;
  } catch {
    return [];
  }
}

/**
 * Grava o arquivo orders.json.
 */
async function writeOrdersJson(req, orders) {
  const { writeFile, mkdir } = await import('node:fs/promises');
  const ordersFile = (req.app && req.app.locals && req.app.locals.ordersFile)
    || process.env.ORDERS_FILE
    || path.resolve(process.cwd(), 'data', 'orders.json');
  await mkdir(path.dirname(ordersFile), { recursive: true });
  await writeFile(ordersFile, JSON.stringify(orders, null, 2) + '\n', 'utf8');
}

/**
 * POST /api/v1/orders/import
 *
 * Legacy endpoint: importa lista de order_id com hub_id opcional.
 * Mantido para compatibilidade com testes e clientes existentes.
 *
 * Body: { orders: [{ order_id, hub_id? }], default_hub_id?, source? }
 * Retorna: { data: [{ order_id, hub_id, source?, imported?, demo_hub_assigned?, hub_preserved? }], total }
 */
router.post('/import', async (req, res) => {
  try {
    if (!req.is('application/json')) {
      return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    }

    const { orders, default_hub_id, source } = req.body ?? {};
    if (!Array.isArray(orders) || orders.length === 0) {
      return res.status(422).json({ error: 'ORDERS_REQUIRED', message: 'Envie uma lista de pedidos no campo "orders".' });
    }

    // Validação: order_id não vazio e sem duplicatas
    const seen = new Set();
    for (const item of orders) {
      const id = typeof item.order_id === 'string' ? item.order_id.trim() : '';
      if (!id) {
        return res.status(422).json({ error: 'INVALID_ORDER_ID', message: 'Todos os pedidos devem ter order_id não vazio.' });
      }
      if (seen.has(id)) {
        return res.status(422).json({ error: 'DUPLICATE_ORDER_ID', message: `order_id duplicado: ${id}` });
      }
      seen.add(id);
    }

    // Usa JSON para compatibilidade com testes e fallback quando DB indisponível
    // O endpoint legacy foi projetado para JSON; PostgreSQL é usado apenas pelo import-csv
    const existingOrders = await readOrdersJson(req);
    const existingMap = new Map(existingOrders.map((o) => [o.order_id, o]));
    const results = [];
    const now = new Date().toISOString();

    for (const item of orders) {
      const id = item.order_id.trim();
      const existing = existingMap.get(id);
      if (existing) {
        if (existing.hub_id) {
          // Preserva hub existente
          const result = { order_id: id, hub_id: existing.hub_id, imported: false, hub_preserved: true };
          if (source !== undefined) result.source = existing.source || source || null;
          results.push(result);
        } else if (default_hub_id) {
          // Atribui default_hub a pedido existente sem hub
          existing.hub_id = default_hub_id;
          const result = { order_id: id, hub_id: default_hub_id, imported: false, demo_hub_assigned: true };
          if (source !== undefined) result.source = existing.source || source || null;
          results.push(result);
        } else {
          const result = { order_id: id, hub_id: null, imported: false };
          if (source !== undefined) result.source = existing.source || source || null;
          results.push(result);
        }
      } else {
        const hubId = item.hub_id || default_hub_id || null;
        const newOrder = { order_id: id, hub_id: hubId, createdAt: now, updatedAt: now };
        if (source !== undefined) newOrder.source = source;
        existingOrders.push(newOrder);
        existingMap.set(id, newOrder);
        const result = { order_id: id, hub_id: hubId || null, imported: true, demo_hub_assigned: !!default_hub_id };
        if (source !== undefined) result.source = source;
        else result.source = null;
        results.push(result);
      }
    }

    await writeOrdersJson(req, existingOrders);
    return res.json({ data: results, total: results.length });
  } catch (error) {
    console.error('Falha no import legacy:', error.message, error.stack);
    return res.status(500).json({ error: 'ORDER_STORAGE_ERROR', message: 'Não foi possível importar os pedidos.' });
  }
});

/**
 * POST /api/v1/orders/import-csv
 *
 * Importa pedidos operacionais a partir de CSV completo.
 *
 * Body: { csv: string }
 * Retorna: { imported, ignored, failed, data: [...] }
 */
router.post('/import-csv', async (req, res) => {
  if (!req.is('application/json')) {
    return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
  }

  const csv = req.body?.csv;
  if (typeof csv !== 'string' || !csv.trim()) {
    return res.status(422).json({ error: 'CSV_REQUIRED', message: 'Envie o conteúdo do CSV no campo "csv".' });
  }

  // Parse CSV
  const lines = csv.trim().split('\n');
  if (lines.length < 2) {
    return res.status(422).json({ error: 'CSV_EMPTY', message: 'O CSV precisa ter cabeçalho e pelo menos um pedido.' });
  }

  const headerRow = parseCsvRecord(lines[0]);
  if (!headerRow) {
    return res.status(422).json({ error: 'CSV_MALFORMED', message: 'Cabeçalho CSV malformado.' });
  }
  const headers = headerRow.map((h) => h.trim().toLowerCase());

  // Validar colunas obrigatórias
  const missingColumns = REQUIRED_COLUMNS.filter((col) => !headers.includes(col));
  if (missingColumns.length > 0) {
    return res.status(422).json({
      error: 'MISSING_COLUMNS',
      message: `Colunas obrigatórias ausentes: ${missingColumns.join(', ')}.`,
      required_columns: REQUIRED_COLUMNS,
    });
  }

  const colIndex = {};
  for (const col of headers) {
    colIndex[col] = headers.indexOf(col);
  }
  const at = (row, name) => {
    const idx = colIndex[name];
    return idx === undefined || idx >= row.length ? '' : row[idx].trim();
  };

  // Processar linhas
  const seenOrderIds = new Set();
  const imported = [];
  const ignored = [];
  const failed = [];

  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    if (!line.trim()) continue;
    const row = parseCsvRecord(line);
    if (!row) {
      failed.push({ line: i + 1, reason: 'Linha CSV malformada' });
      continue;
    }

    const orderId = at(row, 'order_id');
    if (!orderId) {
      failed.push({ line: i + 1, reason: 'order_id vazio' });
      continue;
    }

    // Deduplicação
    if (seenOrderIds.has(orderId)) {
      ignored.push({ order_id: orderId, line: i + 1, reason: 'Duplicado' });
      continue;
    }
    seenOrderIds.add(orderId);

    // Validar CEPs
    const originZip = normalizeCep(at(row, 'origin_zip_code'));
    const destZip = normalizeCep(at(row, 'destination_zip_code'));
    if (!destZip) {
      failed.push({ line: i + 1, order_id: orderId, reason: 'destination_zip_code inválido' });
      continue;
    }

    // Validar datas
    const purchaseAt = at(row, 'purchase_at');
    const dispatchedAt = at(row, 'dispatched_at');
    const estimatedDeliveryAt = at(row, 'estimated_delivery_at');
    if (!purchaseAt || !dispatchedAt || !estimatedDeliveryAt) {
      failed.push({ line: i + 1, order_id: orderId, reason: 'Datas obrigatórias ausentes' });
      continue;
    }

    // Validar UFs
    const sellerState = at(row, 'seller_state').toUpperCase();
    const customerState = at(row, 'customer_state').toUpperCase();
    if (!BRAZILIAN_STATES.has(sellerState)) {
      failed.push({ line: i + 1, order_id: orderId, reason: `seller_state inválido: ${sellerState}` });
      continue;
    }
    if (!BRAZILIAN_STATES.has(customerState)) {
      failed.push({ line: i + 1, order_id: orderId, reason: `customer_state inválido: ${customerState}` });
      continue;
    }

    // Validar números
    const itemsCountResult = parsePositiveInt(at(row, 'items_count'), 'items_count');
    if (itemsCountResult.error) {
      failed.push({ line: i + 1, order_id: orderId, reason: itemsCountResult.error });
      continue;
    }
    const sellersCountResult = parsePositiveInt(at(row, 'sellers_count'), 'sellers_count');
    if (sellersCountResult.error) {
      failed.push({ line: i + 1, order_id: orderId, reason: sellersCountResult.error });
      continue;
    }
    const priceResult = parseNonNegativeFloat(at(row, 'price'), 'price');
    if (priceResult.error) {
      failed.push({ line: i + 1, order_id: orderId, reason: priceResult.error });
      continue;
    }
    const freightResult = parseNonNegativeFloat(at(row, 'freight_value'), 'freight_value');
    if (freightResult.error) {
      failed.push({ line: i + 1, order_id: orderId, reason: freightResult.error });
      continue;
    }

    // Campos opcionais
    const distanceKmRaw = at(row, 'distance_km');
    const distanceKm = distanceKmRaw ? parseNonNegativeFloat(distanceKmRaw, 'distance_km') : null;
    const weightRaw = at(row, 'total_weight_g');
    const totalWeightG = weightRaw ? parseNonNegativeFloat(weightRaw, 'total_weight_g') : null;
    const volumeRaw = at(row, 'total_volume_cm3');
    const totalVolumeCm3 = volumeRaw ? parseNonNegativeFloat(volumeRaw, 'total_volume_cm3') : null;

    // Montar objeto do pedido
    const orderData = {
      order_id: orderId,
      origin_zip_code: originZip || null,
      destination_zip_code: destZip,
      purchase_at: purchaseAt,
      dispatched_at: dispatchedAt,
      estimated_delivery_at: estimatedDeliveryAt,
      seller_state: sellerState,
      customer_state: customerState,
      items_count: itemsCountResult.value,
      sellers_count: sellersCountResult.value,
      price: priceResult.value,
      freight_value: freightResult.value,
      distance_km: distanceKm ? distanceKm.value : null,
      total_weight_g: totalWeightG ? totalWeightG.value : null,
      total_volume_cm3: totalVolumeCm3 ? totalVolumeCm3.value : null,
      source: 'operational',
    };

    // Tentar criar no repositório PostgreSQL
    let orderCreated = false;
    let orderHubId = null;
    try {
      const created = await createOrder(orderData);
      if (created) {
        orderCreated = true;
        orderHubId = created.hub_id || null;
      }
    } catch (e) {
      if (e.code === '23505') {
        ignored.push({ order_id: orderId, line: i + 1, reason: 'Já existe no banco' });
        continue;
      }
      failed.push({ line: i + 1, order_id: orderId, reason: e.message });
      continue;
    }

    // Fallback JSON se PostgreSQL indisponível
    if (!orderCreated) {
      try {
        const existing = await readOrdersJson(req);
        if (existing.find((o) => o.order_id === orderId)) {
          ignored.push({ order_id: orderId, line: i + 1, reason: 'Já existe' });
          continue;
        }
        const newOrder = { ...orderData, created_at: new Date().toISOString(), updated_at: new Date().toISOString() };
        existing.push(newOrder);
        await writeOrdersJson(req, existing);
        orderCreated = true;
      } catch (e) {
        failed.push({ line: i + 1, order_id: orderId, reason: `Erro ao salvar: ${e.message}` });
        continue;
      }
    }

    if (orderCreated) {
      imported.push({
        order_id: orderId,
        destination_zip_code: destZip,
        hub_id: orderHubId,
      });
    }
  }

  // Associar hubs automaticamente após importação
  const dbAvailable = await checkOrdersDb();
  if (dbAvailable && imported.length > 0) {
    try {
      const hubs = await listActiveHubs();
      if (hubs.length > 0) {
        await associateHubsForImported(imported, hubs);
      }
    } catch (e) {
      console.warn('Falha ao associar hubs automaticamente:', e.message);
    }
  }

  return res.json({
    imported: imported.length,
    ignored: ignored.length,
    failed: failed.length,
    data: {
      imported,
      ignored,
      failed,
    },
    total: imported.length + ignored.length + failed.length,
  });
});

/**
 * Associa hubs automaticamente aos pedidos importados.
 */
async function associateHubsForImported(importedOrders, hubs) {
  let geoIndex;
  try {
    geoIndex = await getGeolocationIndex();
  } catch (e) {
    console.warn('Não foi possível carregar índice de geolocalização para associação automática:', e.message);
    return;
  }

  if (!geoIndex) return;

  for (const item of importedOrders) {
    const zipPrefix = item.destination_zip_code.slice(0, 5);
    const geo = geoIndex.get(zipPrefix);
    if (!geo) continue;

    // Encontrar hub mais próximo
    let nearest = null;
    let minDist = Infinity;
    for (const hub of hubs) {
      if (hub.latitude == null || hub.longitude == null) continue;
      const dist = haversineKm(geo.latitude, geo.longitude, hub.latitude, hub.longitude);
      if (dist < minDist || (dist === minDist && (nearest === null || hub.id < nearest.id))) {
        minDist = dist;
        nearest = hub;
      }
    }

    if (nearest) {
      await associateHub(
        item.order_id,
        nearest.id,
        `Hub mais próximo: ${minDist.toFixed(2)} km`
      );
      item.hub_id = nearest.id;
    }
  }
}

/**
 * GET /api/v1/orders
 * Lista pedidos com paginação e filtros.
 */
router.get('/', async (req, res) => {
  const parsePositiveInt = (value, defaultValue, max) => {
    if (value === undefined) return { value: defaultValue };
    const parsed = parseInt(value, 10);
    if (!Number.isFinite(parsed) || parsed < 1 || parsed > max) return { error: true };
    return { value: parsed };
  };

  const pageResult = parsePositiveInt(req.query.page, 1, 9999);
  const perPageResult = parsePositiveInt(req.query.per_page, 50, 500);
  if (pageResult.error || perPageResult.error) {
    return res.status(422).json({ error: 'INVALID_PAGE', message: 'Parâmetros de paginação inválidos.' });
  }

  // Validate hub_id if provided
  if (req.query.hub_id !== undefined && req.query.hub_id !== null && !req.query.hub_id.trim()) {
    return res.status(422).json({ error: 'INVALID_HUB_ID', message: 'hub_id inválido.' });
  }

  try {
    let result = await listOrders({
      page: pageResult.value,
      perPage: perPageResult.value,
      hubId: req.query.hub_id?.trim() || null,
      search: req.query.q?.trim() || null,
      source: req.query.source?.trim() || null,
    });

    // Fallback para JSON se PostgreSQL indisponível ou sem dados
    const dbOk = await checkOrdersDb();
    if (!dbOk || (result.data.length === 0 && result.total === 0)) {
      // Fallback: ler do JSON
      try {
        const { readFile: fsReadFile } = await import('node:fs/promises');
        const ordersFile = (req.app && req.app.locals && req.app.locals.ordersFile)
          || process.env.ORDERS_FILE
          || path.resolve(process.cwd(), 'data', 'orders.json');
        const content = await fsReadFile(ordersFile, 'utf8');
        const allOrders = JSON.parse(content);
        if (Array.isArray(allOrders)) {
          // Apply filters
          let filtered = allOrders;
          if (req.query.hub_id?.trim()) {
            filtered = filtered.filter((o) => o.hub_id === req.query.hub_id.trim());
          }
          if (req.query.q?.trim()) {
            const q = req.query.q.trim().toLowerCase();
            filtered = filtered.filter((o) => (o.order_id || '').toLowerCase().includes(q));
          }
          if (req.query.source?.trim()) {
            filtered = filtered.filter((o) => (o.source || 'operational') === req.query.source.trim());
          }
          const total = filtered.length;
          const offset = (pageResult.value - 1) * perPageResult.value;
          const paged = filtered.slice(offset, offset + perPageResult.value);
          result = { data: paged, total, page: pageResult.value, perPage: perPageResult.value };
        }
      } catch (e) {
        // Se o arquivo existe mas tem JSON inválido, é erro de armazenamento
        if (e.code === 'ENOENT') {
          // Arquivo não existe; retornar vazio
        } else if (e instanceof SyntaxError) {
          // JSON inválido; propagar erro 500
          throw e;
        }
        // Outro erro; retornar vazio
      }
    }

    // Enrich with hub info — DB first, then merge with JSON fallback
    let hubsMap = new Map();
    try {
      const hubs = await listActiveHubs();
      if (hubs.length > 0) {
        hubsMap = new Map(hubs.map((h) => [h.id, h]));
      }
      // Always merge JSON hubs (for tests with custom hubs, or orders from JSON)
      try {
        const hubsJson = await readHubsFromJson(req);
        for (const h of hubsJson) {
          if (!hubsMap.has(h.id)) {
            hubsMap.set(h.id, h);
          }
        }
      } catch (e3) {
        // Ignore JSON hub read errors
      }
    } catch (e) {
      // Fallback para hubs JSON
      try {
        const hubsJson = await readHubsFromJson(req);
        hubsMap = new Map(hubsJson.map((h) => [h.id, h]));
      } catch (e2) {
        // No hubs available
      }
    }

    const enriched = result.data.map((order) => ({
      order_id: order.order_id,
      origin_zip_code: order.origin_zip_code,
      destination_zip_code: order.destination_zip_code,
      purchase_at: order.purchase_at,
      dispatched_at: order.dispatched_at,
      estimated_delivery_at: order.estimated_delivery_at,
      seller_state: order.seller_state,
      customer_state: order.customer_state,
      items_count: order.items_count,
      sellers_count: order.sellers_count,
      price: order.price,
      freight_value: order.freight_value,
      hub_id: order.hub_id || null,
      hub: order.hub_id && hubsMap.has(order.hub_id)
        ? { id: hubsMap.get(order.hub_id).id, code: hubsMap.get(order.hub_id).code, name: hubsMap.get(order.hub_id).name, city: hubsMap.get(order.hub_id).city, state: hubsMap.get(order.hub_id).state }
        : null,
      source: order.source || 'operational',
      created_at: order.created_at,
      updated_at: order.updated_at,
    }));

    return res.json({
      data: enriched,
      total: result.total,
      page: result.page,
      per_page: result.perPage,
      total_pages: Math.ceil(result.total / result.perPage) || 1,
    });
  } catch (error) {
    console.error('Falha ao listar pedidos:', error.message);
    return res.status(500).json({ error: 'ORDER_STORAGE_ERROR', message: 'Não foi possível consultar os pedidos.' });
  }
});

/**
 * GET /api/v1/orders/summary
 * Retorna resumo dos pedidos operacionais.
 */
router.get('/summary', async (req, res) => {
  try {
    // Try PostgreSQL first
    const dbSummary = await ordersSummary();
    if (dbSummary) {
      return res.json({ data: dbSummary });
    }

    // Fallback: count from JSON
    const ordersJson = await readOrdersJson(req);
    const operational = ordersJson.filter((o) => (o.source || 'operational') === 'operational');
    const total = operational.length;
    const withHub = operational.filter((o) => o.hub_id).length;
    const withoutHub = total - withHub;
    // For JSON fallback, we can't easily count predictions; return 0
    return res.json({
      data: {
        total,
        withHub,
        withoutHub,
        withPrediction: 0,
      },
    });
  } catch (error) {
    console.error('Falha ao calcular resumo:', error.message);
    return res.status(500).json({ error: 'ORDER_STORAGE_ERROR', message: 'Não foi possível consultar os pedidos.' });
  }
});

/**
 * GET /api/v1/orders/:orderId
 * Detalhe de um pedido.
 */
router.get('/:orderId', async (req, res) => {
  const orderId = normalizeOrderId(req.params.orderId);
  if (!orderId) return res.status(422).json({ error: 'INVALID_ORDER_ID', message: 'order_id inválido.' });

  try {
    let order = await findOrderById(orderId);
    // Fallback para JSON se DB indisponível
    if (!order) {
      const ordersJson = await readOrdersJson(req);
      order = ordersJson.find((o) => o.order_id === orderId);
    }
    if (!order) return res.status(404).json({ error: 'ORDER_NOT_FOUND', message: 'O pedido não foi encontrado.' });

    let hub = order.hub_id ? await findHubById(order.hub_id) : null;
    if (!hub && order.hub_id) {
      const hubsJson = await readHubsFromJson(req);
      hub = hubsJson.find((h) => h.id === order.hub_id) || null;
    }

    return res.json({ data: {
      order_id: order.order_id,
      origin_zip_code: order.origin_zip_code,
      destination_zip_code: order.destination_zip_code,
      purchase_at: order.purchase_at,
      dispatched_at: order.dispatched_at,
      estimated_delivery_at: order.estimated_delivery_at,
      seller_state: order.seller_state,
      customer_state: order.customer_state,
      items_count: order.items_count,
      sellers_count: order.sellers_count,
      price: order.price,
      freight_value: order.freight_value,
      distance_km: order.distance_km,
      total_weight_g: order.total_weight_g,
      total_volume_cm3: order.total_volume_cm3,
      hub_id: order.hub_id || null,
      hub: hub ? { id: hub.id, code: hub.code, name: hub.name, city: hub.city, state: hub.state } : null,
      source: order.source || 'operational',
      created_at: order.created_at,
      updated_at: order.updated_at,
    }});
  } catch (error) {
    console.error('Falha ao ler pedido:', error.message);
    return res.status(500).json({ error: 'ORDER_STORAGE_ERROR', message: 'Não foi possível consultar o pedido.' });
  }
});

/**
 * Lê hubs do arquivo JSON (fallback enquanto hubs não estão no PostgreSQL).
 */
async function readHubsFromJson(req) {
  const { readFile } = await import('node:fs/promises');
  const hubsFile = (req && req.app && req.app.locals && req.app.locals.hubsFile)
    || process.env.HUBS_FILE
    || `${process.cwd()}/data/hubs.json`;
  try {
    const content = await readFile(hubsFile, 'utf8');
    const parsed = JSON.parse(content);
    if (!Array.isArray(parsed)) return [];
    return parsed;
  } catch {
    return [];
  }
}

/**
 * PATCH /api/v1/orders/:orderId/hub
 * Altera manualmente o hub de um pedido.
 */
router.patch('/:orderId/hub', async (req, res) => {
  if (!req.is('application/json')) {
    return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
  }

  const orderId = normalizeOrderId(req.params.orderId);
  if (!orderId) return res.status(422).json({ error: 'INVALID_ORDER_ID', message: 'order_id inválido.' });

  if (!Object.hasOwn(req.body ?? {}, 'hub_id')) {
    return res.status(422).json({ error: 'HUB_ID_REQUIRED', message: 'Envie hub_id.' });
  }

  const hubId = req.body.hub_id;
  if (hubId !== null && (typeof hubId !== 'string' || !hubId.trim())) {
    return res.status(422).json({ error: 'INVALID_HUB_ID', message: 'hub_id inválido.' });
  }

  try {
    // Validar hub se não for null — primeiro no DB, depois no JSON
    if (hubId !== null) {
      let hub = await findHubById(hubId);
      if (!hub) {
        const hubsJson = await readHubsFromJson(req);
        hub = hubsJson.find((h) => h.id === hubId);
      }
      if (!hub) {
        return res.status(404).json({ error: 'HUB_NOT_FOUND', message: 'O hub informado não existe.' });
      }
    }

    // Tenta PostgreSQL primeiro
    let order = await updateOrderHub(orderId, hubId);
    // Fallback para JSON se DB indisponível
    if (!order) {
      const ordersJson = await readOrdersJson(req);
      const idx = ordersJson.findIndex((o) => o.order_id === orderId);
      if (idx < 0) {
        return res.status(404).json({ error: 'ORDER_NOT_FOUND', message: 'O pedido não foi encontrado.' });
      }
      const now = new Date().toISOString();
      ordersJson[idx] = { ...ordersJson[idx], hub_id: hubId, hub_association_manual: true, updatedAt: now };
      await writeOrdersJson(req, ordersJson);
      order = ordersJson[idx];
    }

    // Look up hub info for response
    let hubInfo = null;
    if (order.hub_id) {
      hubInfo = await findHubById(order.hub_id);
      if (!hubInfo) {
        const hubsJson = await readHubsFromJson(req);
        hubInfo = hubsJson.find((h) => h.id === order.hub_id) || null;
      }
    }

    return res.json({ data: {
      order_id: order.order_id,
      hub_id: order.hub_id || null,
      hub: hubInfo ? { id: hubInfo.id, code: hubInfo.code, name: hubInfo.name, city: hubInfo.city, state: hubInfo.state } : null,
      updated_at: order.updated_at || order.updatedAt,
    }});
  } catch (error) {
    console.error('Falha ao atualizar hub do pedido:', error.message);
    return res.status(500).json({ error: 'ORDER_STORAGE_ERROR', message: 'Não foi possível atualizar o hub.' });
  }
});

export default router;
