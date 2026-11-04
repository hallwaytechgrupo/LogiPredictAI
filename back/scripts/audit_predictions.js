#!/usr/bin/env node

/**
 * Script de auditoria: compara pedidos importados com previsões existentes.
 *
 * Lê os arquivos JSON do backend em modo de leitura — não modifica nenhum dado.
 * Se os arquivos não forem acessíveis, usa a API como fallback.
 *
 * Uso:
 *   node scripts/audit_predictions.js [opções]
 *
 * Opções:
 *   --orders <path>        Caminho para orders.json (padrão: data/hubs/orders.json)
 *   --predictions <path>   Caminho para predictions.json (padrão: data/hubs/predictions.json)
 *   --journal <path>       Caminho para predictions.jsonl (padrão: data/hubs/predictions.jsonl)
 *   --sample <n>           Número de IDs a exibir na lista de pedidos sem previsão (padrão: 20)
 *   --base-dir <path>      Diretório base para resolver caminhos relativos (padrão: process.cwd())
 *   --api-url <url>        URL da API para fallback (padrão: detecta automaticamente)
 */

import { readFile, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ── Argumentos ────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const args = { sample: 20 };
  for (let i = 2; i < argv.length; i++) {
    switch (argv[i]) {
      case '--orders':
        args.orders = argv[++i];
        break;
      case '--predictions':
        args.predictions = argv[++i];
        break;
      case '--journal':
        args.journal = argv[++i];
        break;
      case '--sample':
        args.sample = parseInt(argv[++i], 10) || 20;
        break;
      case '--base-dir':
        args.baseDir = argv[++i];
        break;
      case '--api-url':
        args.apiUrl = argv[++i];
        break;
      default:
        console.error(`Aviso: argumento desconhecido "${argv[i]}"`);
    }
  }
  return args;
}

const args = parseArgs(process.argv);
const baseDir = args.baseDir || process.cwd();

// Caminhos padrão — usam a mesma lógica do app.js
const ordersFile = args.orders || path.resolve(baseDir, 'data', 'hubs', 'orders.json');
const predictionsFile = args.predictions || path.resolve(baseDir, 'data', 'hubs', 'predictions.json');
const journalFile = args.journal || path.resolve(baseDir, 'data', 'hubs', 'predictions.jsonl');

// ── Detecção da API ───────────────────────────────────────────────────────────

async function detectApiUrl() {
  // Tenta portas comuns onde a API pode estar rodando
  const ports = [3000, 3001, 8080];
  for (const port of ports) {
    try {
      const resp = await fetch(`http://127.0.0.1:${port}/health`, { signal: AbortSignal.timeout(2000) });
      if (resp.ok) {
        const data = await resp.json();
        if (data.service === 'logipredict-api') {
          return `http://127.0.0.1:${port}`;
        }
      }
    } catch {
      // Porta indisponível, tenta a próxima
    }
  }
  return null;
}

// ── Leitura segura com fallback via API ───────────────────────────────────────

let apiUrl = null;
let apiAvailable = false;

async function ensureApi() {
  if (apiUrl !== null) return;
  apiUrl = args.apiUrl || await detectApiUrl();
  apiAvailable = apiUrl !== null;
}

async function fetchJson(urlPath) {
  if (!apiAvailable || !apiUrl) return null;
  try {
    const resp = await fetch(`${apiUrl}${urlPath}`, { signal: AbortSignal.timeout(30000) });
    if (!resp.ok) return null;
    return await resp.json();
  } catch {
    return null;
  }
}

async function readJsonArray(filePath, label) {
  try {
    const content = await readFile(filePath, 'utf8');
    const parsed = JSON.parse(content);
    if (!Array.isArray(parsed)) {
      console.error(`Aviso: ${label} não é um array JSON. Arquivo: ${filePath}`);
      return [];
    }
    return parsed;
  } catch (error) {
    if (error.code === 'ENOENT') {
      console.error(`Aviso: arquivo não encontrado — ${filePath}`);
      return [];
    }
    if (error.code === 'EACCES') {
      console.error(`  (Permissão negada para ${filePath} — usando API como fallback)`);
      await ensureApi();
      if (apiAvailable) {
        return await readFromApi(label);
      }
      console.error(`Erro: API não disponível. Não é possível ler ${filePath}.`);
      console.error('Tente executar o script com permissões adequadas ou inicie a API.');
      process.exit(1);
    }
    console.error(`Erro ao ler ${label} (${filePath}): ${error.message}`);
    return [];
  }
}

async function readJournal(filePath) {
  const records = [];
  try {
    const content = await readFile(filePath, 'utf8');
    for (const [index, line] of content.split('\n').entries()) {
      if (!line.trim()) continue;
      try {
        const record = JSON.parse(line);
        if (!record || typeof record !== 'object' || Array.isArray(record)) {
          console.error(`Aviso: registro inválido na linha ${index + 1} do journal`);
          continue;
        }
        records.push(record);
      } catch {
        console.error(`Aviso: JSON inválido na linha ${index + 1} do journal`);
      }
    }
  } catch (error) {
    if (error.code === 'ENOENT') {
      console.error(`Aviso: journal não encontrado — ${filePath}`);
      return [];
    }
    if (error.code === 'EACCES') {
      console.error(`  (Permissão negada para ${filePath} — usando API como fallback)`);
      await ensureApi();
      return await readPredictionsFromApi();
    }
    console.error(`Erro ao ler journal (${filePath}): ${error.message}`);
    return [];
  }
  return records;
}

async function readFromApi(label) {
  // A API não expõe listagem completa de orders ou predictions individuais.
  // O script usará o endpoint analytics/hubs para obter os agregados.
  return [];
}

async function readPredictionsFromApi() {
  // O endpoint analytics/hubs retorna agregados, não previsões individuais.
  // O script usará esses agregados para a auditoria.
  return [];
}

// ── Validação de order_id ─────────────────────────────────────────────────────

function isValidOrderId(id) {
  return typeof id === 'string' && id.trim().length > 0;
}

// ── Auditoria ─────────────────────────────────────────────────────────────────

async function runAudit() {
  console.log('═'.repeat(72));
  console.log('  AUDITORIA: Pedidos Importados vs Previsões Existentes');
  console.log('═'.repeat(72));
  console.log();

  // Arquivos
  console.log('Arquivos configurados:');
  console.log(`  Pedidos:       ${ordersFile}`);
  console.log(`  Previsões:     ${predictionsFile}`);
  console.log(`  Journal:       ${journalFile}`);
  console.log();

  // Ler dados
  const [orders, predictionsMain, journalRecords] = await Promise.all([
    readJsonArray(ordersFile, 'orders.json'),
    readJsonArray(predictionsFile, 'predictions.json'),
    readJournal(journalFile),
  ]);

  const allPredictions = [...predictionsMain, ...journalRecords];

  // Se não conseguimos ler os arquivos diretamente, tentamos via API
  const useApiFallback = orders.length === 0 && allPredictions.length === 0;
  let apiHubData = null;
  let apiOrderCount = null;

  if (useApiFallback) {
    await ensureApi();
    if (apiAvailable) {
      console.log(`  API detectada: ${apiUrl}`);
      console.log('  Obtendo dados via endpoint analytics/hubs...');
      apiHubData = await fetchJson('/api/v1/analytics/hubs');
    } else {
      console.log('  API não disponível. Resultados limitados.');
    }
  }

  // ── Pedidos importados ──────────────────────────────────────────────────

  const orderIds = new Set();
  let ordersWithNullId = 0;

  for (const order of orders) {
    if (!order || typeof order !== 'object') continue;
    const id = order.order_id;
    if (isValidOrderId(id)) {
      orderIds.add(id.trim());
    } else {
      ordersWithNullId++;
    }
  }

  // ── Previsões ───────────────────────────────────────────────────────────

  const predictionOrderIds = new Set();
  const predictionCountByOrder = new Map();
  let predictionsWithNullId = 0;

  for (const pred of allPredictions) {
    const id = pred.order_id;
    if (isValidOrderId(id)) {
      const trimmed = id.trim();
      predictionOrderIds.add(trimmed);
      predictionCountByOrder.set(trimmed, (predictionCountByOrder.get(trimmed) || 0) + 1);
    } else {
      predictionsWithNullId++;
    }
  }

  // Pedidos com previsão duplicada (mais de 1 registro no journal)
  const duplicatedOrders = [...predictionCountByOrder.entries()]
    .filter(([, count]) => count > 1)
    .sort((a, b) => b[1] - a[1]);

  const totalDuplicateRecords = duplicatedOrders.reduce(
    (sum, [, count]) => sum + (count - 1), 0
  );

  // ── Comparação por conjuntos ────────────────────────────────────────────

  // Pedidos importados sem previsão
  const importedWithoutPrediction = [...orderIds].filter((id) => !predictionOrderIds.has(id));

  // Previsões cujo order_id não existe nos pedidos importados
  const predictionsWithoutImportedOrder = [...predictionOrderIds].filter(
    (id) => !orderIds.has(id)
  );

  // Pedidos com previsão (interseção)
  const importedWithPrediction = [...orderIds].filter((id) => predictionOrderIds.has(id));

  // ── Estatísticas por hub (a partir das previsões) ──────────────────────

  const hubStats = new Map();
  for (const pred of allPredictions) {
    const hubId = pred.hub_id;
    if (!isValidOrderId(hubId)) continue;
    if (!hubStats.has(hubId)) {
      hubStats.set(hubId, { count: 0, uniqueOrders: new Set() });
    }
    const stat = hubStats.get(hubId);
    stat.count++;
    if (isValidOrderId(pred.order_id)) {
      stat.uniqueOrders.add(pred.order_id.trim());
    }
  }

  // ── Versões do modelo ──────────────────────────────────────────────────

  const modelVersions = new Map();
  for (const pred of allPredictions) {
    const version = pred.model_version;
    if (typeof version === 'string' && version) {
      modelVersions.set(version, (modelVersions.get(version) || 0) + 1);
    }
  }

  // ── Relatório ───────────────────────────────────────────────────────────

  console.log('─'.repeat(72));
  console.log('  RESULTADOS DA AUDITORIA');
  console.log('─'.repeat(72));
  console.log();

  // Se usou fallback via API, mostra os dados da API
  if (useApiFallback && apiHubData && apiHubData.data) {
    const hubList = apiHubData.data;
    const totalPredictionsDeduped = hubList.reduce((sum, h) => sum + h.predictions_count, 0);
    const totalRiskDeduped = hubList.reduce((sum, h) => sum + h.risk_count, 0);

    console.log('┌─ DADOS VIA API (arquivos não acessíveis) ─────────────────────────────────┐');
    console.log(`│ Fonte: Endpoint GET /api/v1/analytics/hubs                              │`);
    console.log(`│ (Deduplicação por order_id já aplicada pela API)                        │`);
    console.log('└────────────────────────────────────────────────────────────────────────────┘');
    console.log();

    console.log('┌─ PEDIDOS IMPORTADOS ──────────────────────────────────────────────────────┐');
    console.log(`│ Não disponível — arquivos sem permissão de leitura                      │`);
    console.log('└────────────────────────────────────────────────────────────────────────────┘');
    console.log();

    console.log('┌─ PREVISÕES (deduplicadas pela API) ───────────────────────────────────────┐');
    console.log(`│ Hubs com previsões:                       ${String(apiHubData.total).padStart(40)} │`);
    console.log(`│ Pedidos únicos com previsão:              ${String(totalPredictionsDeduped).padStart(40)} │`);
    console.log(`│ Pedidos com risco (predicted_late=true):  ${String(totalRiskDeduped).padStart(40)} │`);
    const riskPct = totalPredictionsDeduped > 0
      ? ((totalRiskDeduped / totalPredictionsDeduped) * 100).toFixed(2)
      : 'N/A';
    console.log(`│ Percentual de risco:                      ${String(riskPct + '%').padStart(40)} │`);
    console.log('└────────────────────────────────────────────────────────────────────────────┘');
    console.log();

    // Versões do modelo
    if (apiHubData.data.length > 0) {
      const versions = new Set();
      for (const h of hubList) {
        if (h.model_version) versions.add(h.model_version);
      }
      if (versions.size > 0) {
        console.log('┌─ VERSÕES DO MODELO ────────────────────────────────────────────────────────┐');
        for (const v of [...versions].sort()) {
          console.log(`│ ${v.padEnd(40)} │`);
        }
        console.log('└────────────────────────────────────────────────────────────────────────────┘');
        console.log();
      }
    }

    // Top hubs
    const topHubs = [...hubList].sort((a, b) => b.predictions_count - a.predictions_count).slice(0, 10);
    console.log('┌─ TOP 10 HUBS POR PREVISÕES ────────────────────────────────────────────────┐');
    console.log(`│ Hub ID (prefixo)                    Previsões   Risco                      │`);
    console.log(`│ ${'─'.repeat(42)} ${'─'.repeat(11)} ${'─'.repeat(22)} │`);
    for (const h of topHubs) {
      const prefix = h.hub_id.length > 42 ? h.hub_id.slice(0, 39) + '...' : h.hub_id.padEnd(42);
      console.log(`│ ${prefix} ${String(h.predictions_count).padStart(11)} ${String(h.risk_count).padStart(22)} │`);
    }
    console.log('└────────────────────────────────────────────────────────────────────────────┘');
    console.log();

    console.log('═'.repeat(72));
    console.log('  Auditoria concluída (modo API). Nenhum dado foi modificado.');
    console.log('  Para auditoria completa, execute com permissão de leitura nos arquivos.');
    console.log('═'.repeat(72));
    return;
  }

  console.log('┌─ PEDIDOS IMPORTADOS ──────────────────────────────────────────────────────┐');
  console.log(`│ Total de registros em orders.json:            ${String(orders.length).padStart(40)} │`);
  console.log(`│ order_id únicos importados:                   ${String(orderIds.size).padStart(40)} │`);
  if (ordersWithNullId > 0) {
    console.log(`│ Registros com order_id nulo/inválido:         ${String(ordersWithNullId).padStart(40)} │`);
  }
  console.log('└────────────────────────────────────────────────────────────────────────────┘');
  console.log();

  console.log('┌─ PREVISÕES ────────────────────────────────────────────────────────────────┐');
  console.log(`│ Registros em predictions.json:                ${String(predictionsMain.length).padStart(40)} │`);
  console.log(`│ Registros no journal (predictions.jsonl):     ${String(journalRecords.length).padStart(40)} │`);
  console.log(`│ Total de registros de previsão:               ${String(allPredictions.length).padStart(40)} │`);
  console.log(`│ Pedidos únicos com previsão:                  ${String(predictionOrderIds.size).padStart(40)} │`);
  if (predictionsWithNullId > 0) {
    console.log(`│ Previsões com order_id nulo/inválido:         ${String(predictionsWithNullId).padStart(40)} │`);
  }
  console.log(`│ Previsões duplicadas por order_id:            ${String(totalDuplicateRecords).padStart(40)} │`);
  console.log(`│ Pedidos com mais de 1 previsão:               ${String(duplicatedOrders.length).padStart(40)} │`);
  console.log('└────────────────────────────────────────────────────────────────────────────┘');
  console.log();

  console.log('┌─ COMPARAÇÃO ───────────────────────────────────────────────────────────────┐');
  console.log(`│ Pedidos importados com previsão:              ${String(importedWithPrediction.length).padStart(40)} │`);
  console.log(`│ Pedidos importados sem previsão:              ${String(importedWithoutPrediction.length).padStart(40)} │`);
  console.log(`│ Previsões sem pedido importado correspondente: ${String(predictionsWithoutImportedOrder.length).padStart(40)} │`);
  console.log('└────────────────────────────────────────────────────────────────────────────┘');
  console.log();

  // Cobertura
  const coverage = orderIds.size > 0
    ? ((importedWithPrediction.length / orderIds.size) * 100).toFixed(2)
    : 'N/A';
  console.log(`  Cobertura de previsão: ${coverage}% (${importedWithPrediction.length} de ${orderIds.size} pedidos)`);
  console.log();

  // Versões do modelo
  if (modelVersions.size > 0) {
    console.log('┌─ VERSÕES DO MODELO ────────────────────────────────────────────────────────┐');
    for (const [version, count] of [...modelVersions.entries()].sort((a, b) => b[1] - a[1])) {
      console.log(`│ ${version.padEnd(40)} ${String(count).padStart(15)} registros │`);
    }
    console.log('└────────────────────────────────────────────────────────────────────────────┘');
    console.log();
  }

  // Top hubs por previsão
  if (hubStats.size > 0) {
    const topHubs = [...hubStats.entries()]
      .map(([hubId, stat]) => ({ hubId, ...stat }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 10);

    console.log('┌─ TOP 10 HUBS POR REGISTROS DE PREVISÃO ────────────────────────────────────┐');
    console.log(`│ Hub ID (prefixo)                    Registros   Pedidos únicos             │`);
    console.log(`│ ${'─'.repeat(42)} ${'─'.repeat(12)} ${'─'.repeat(18)} │`);
    for (const { hubId, count, uniqueOrders } of topHubs) {
      const prefix = hubId.length > 42 ? hubId.slice(0, 39) + '...' : hubId.padEnd(42);
      console.log(`│ ${prefix} ${String(count).padStart(12)} ${String(uniqueOrders.size).padStart(18)} │`);
    }
    console.log('└────────────────────────────────────────────────────────────────────────────┘');
    console.log();
  }

  // Top duplicatas
  if (duplicatedOrders.length > 0) {
    const topDups = duplicatedOrders.slice(0, 10);
    console.log('┌─ TOP 10 PEDIDOS COM MAIS PREVISÕES DUPLICADAS ─────────────────────────────┐');
    console.log(`│ Order ID (prefixo)                        Contagem                         │`);
    console.log(`│ ${'─'.repeat(42)} ${'─'.repeat(28)} │`);
    for (const [orderId, count] of topDups) {
      const prefix = orderId.length > 42 ? orderId.slice(0, 39) + '...' : orderId.padEnd(42);
      console.log(`│ ${prefix} ${String(count).padStart(28)} │`);
    }
    console.log('└────────────────────────────────────────────────────────────────────────────┘');
    console.log();
  }

  // Amostra de pedidos sem previsão
  if (importedWithoutPrediction.length > 0) {
    const sampleSize = Math.min(args.sample, importedWithoutPrediction.length);
    console.log(`┌─ AMOSTRA DE PEDIDOS IMPORTADOS SEM PREVISÃO (${sampleSize} de ${importedWithoutPrediction.length}) ─────────────┐`);
    for (const id of importedWithoutPrediction.slice(0, sampleSize)) {
      console.log(`│   ${id}`);
    }
    console.log('└────────────────────────────────────────────────────────────────────────────┘');
    console.log();
  }

  // Previsões sem pedido importado
  if (predictionsWithoutImportedOrder.length > 0) {
    const sampleSize = Math.min(args.sample, predictionsWithoutImportedOrder.length);
    console.log(`┌─ AMOSTRA DE PREVISÕES SEM PEDIDO IMPORTADO (${sampleSize} de ${predictionsWithoutImportedOrder.length}) ────────────┐`);
    for (const id of predictionsWithoutImportedOrder.slice(0, sampleSize)) {
      console.log(`│   ${id}`);
    }
    console.log('└────────────────────────────────────────────────────────────────────────────┘');
    console.log();
  }

  console.log('═'.repeat(72));
  console.log('  Auditoria concluída. Nenhum dado foi modificado.');
  console.log('═'.repeat(72));
}

runAudit().catch((error) => {
  console.error('Erro fatal durante a auditoria:', error.message);
  process.exit(1);
});
