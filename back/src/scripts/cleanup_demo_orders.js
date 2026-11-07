/// Script para remover pedidos DEMO-OLIST do sistema.
///
/// Executa: `node src/scripts/cleanup_demo_orders.js`
///
/// Remove:
/// - Pedidos com order_id começando com "DEMO-OLIST" do orders.json
/// - Previsões com order_id começando com "DEMO-OLIST" do predictions.jsonl
/// - Registros do PostgreSQL (se disponível)
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { getKnex, destroyKnex } from '../db/knex.js';

const DEMO_PREFIX = 'DEMO-OLIST';
const ORDERS_FILE = process.env.ORDERS_FILE || './data/hubs/orders.json';
const PREDICTIONS_FILE = process.env.PREDICTIONS_FILE || './data/hubs/predictions.jsonl';

async function cleanupJson() {
  let ordersRemoved = 0;
  let predictionsRemoved = 0;

  // Clean orders.json
  if (existsSync(ORDERS_FILE)) {
    try {
      const orders = JSON.parse(readFileSync(ORDERS_FILE, 'utf8'));
      const before = orders.length;
      const filtered = orders.filter((o) => !(o.order_id || '').startsWith(DEMO_PREFIX));
      if (filtered.length < before) {
        writeFileSync(ORDERS_FILE, JSON.stringify(filtered, null, 0));
        ordersRemoved = before - filtered.length;
        console.log(`[orders.json] Removidos ${ordersRemoved} pedidos ${DEMO_PREFIX}. Restantes: ${filtered.length}`);
      } else {
        console.log(`[orders.json] Nenhum pedido ${DEMO_PREFIX} encontrado.`);
      }
    } catch (err) {
      console.error(`[orders.json] Erro ao processar: ${err.message}`);
    }
  } else {
    console.log(`[orders.json] Arquivo não encontrado: ${ORDERS_FILE}`);
  }

  // Clean predictions.jsonl
  if (existsSync(PREDICTIONS_FILE)) {
    try {
      const lines = readFileSync(PREDICTIONS_FILE, 'utf8')
        .trim()
        .split('\n')
        .filter((l) => l.trim().length > 0);
      const before = lines.length;
      const filtered = lines.filter((line) => {
        try {
          const p = JSON.parse(line);
          return !(p.order_id || '').startsWith(DEMO_PREFIX);
        } catch {
          return true; // keep unparseable lines
        }
      });
      if (filtered.length < before) {
        writeFileSync(PREDICTIONS_FILE, filtered.join('\n') + '\n');
        predictionsRemoved = before - filtered.length;
        console.log(`[predictions.jsonl] Removidas ${predictionsRemoved} previsões ${DEMO_PREFIX}. Restantes: ${filtered.length}`);
      } else {
        console.log(`[predictions.jsonl] Nenhuma previsão ${DEMO_PREFIX} encontrada.`);
      }
    } catch (err) {
      console.error(`[predictions.jsonl] Erro ao processar: ${err.message}`);
    }
  } else {
    console.log(`[predictions.jsonl] Arquivo não encontrado: ${PREDICTIONS_FILE}`);
  }

  return { ordersRemoved, predictionsRemoved };
}

async function cleanupPostgres() {
  let ordersRemoved = 0;
  let predictionsRemoved = 0;

  try {
    const db = getKnex();
    const hasTable = await db.schema.hasTable('orders').catch(() => false);

    if (hasTable) {
      // Delete predictions first (FK constraint)
      const predDel = await db('predictions')
        .where('order_id', 'like', `${DEMO_PREFIX}%`)
        .del();
      predictionsRemoved = predDel;
      console.log(`[PostgreSQL] Removidas ${predictionsRemoved} previsões ${DEMO_PREFIX} da tabela predictions.`);

      // Delete orders
      const orderDel = await db('orders')
        .where('order_id', 'like', `${DEMO_PREFIX}%`)
        .del();
      ordersRemoved = orderDel;
      console.log(`[PostgreSQL] Removidos ${ordersRemoved} pedidos ${DEMO_PREFIX} da tabela orders.`);

      await destroyKnex();
    } else {
      console.log('[PostgreSQL] Tabela orders não encontrada. Pulando limpeza do banco.');
    }
  } catch (err) {
    console.error(`[PostgreSQL] Erro ao conectar: ${err.message}`);
  }

  return { ordersRemoved, predictionsRemoved };
}

async function main() {
  console.log(`\n=== Limpeza de pedidos ${DEMO_PREFIX} ===\n`);

  const json = await cleanupJson();
  const pg = await cleanupPostgres();

  const totalOrders = json.ordersRemoved + pg.ordersRemoved;
  const totalPredictions = json.predictionsRemoved + pg.predictionsRemoved;

  console.log(`\n=== Resumo ===`);
  console.log(`Pedidos removidos: ${totalOrders} (JSON: ${json.ordersRemoved}, PostgreSQL: ${pg.ordersRemoved})`);
  console.log(`Previsões removidas: ${totalPredictions} (JSONL: ${json.predictionsRemoved}, PostgreSQL: ${pg.predictionsRemoved})`);
  console.log();
}

main().catch((err) => {
  console.error('Erro fatal:', err);
  process.exit(1);
});
