/**
 * Ponto de entrada do servidor backend LogiPredictAI.
 *
 * Lê as variáveis de ambiente, valida as configurações e inicia o servidor Express.
 * Suporta desligamento gracioso via SIGINT/SIGTERM com timeout de 10 segundos.
 *
 * Variáveis de ambiente:
 *   PORT          - Porta do servidor (padrão: 3001).
 *   HOST          - Host para vinculação (padrão: 127.0.0.1).
 *   ML_URL        - URL do serviço ML FastAPI (padrão: http://127.0.0.1:8000).
 *   ML_TIMEOUT_MS - Timeout em ms para chamadas ao ML (padrão: 10000).
 */
import './load-env.js';
import { createApp } from './app.js';
import { PostgresStore } from './db/cloud-store.js';
import { readFile } from 'node:fs/promises';

const port = Number(process.env.PORT ?? 3001);
const timeoutMs = Number(process.env.ML_TIMEOUT_MS ?? 10000);
const mlUrl = new URL(process.env.ML_URL ?? 'http://127.0.0.1:8000');
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT inválida.');
if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 120000) throw new Error('ML_TIMEOUT_MS inválido.');
if (!['http:', 'https:'].includes(mlUrl.protocol)) throw new Error('ML_URL deve usar HTTP ou HTTPS.');
const host = process.env.HOST ?? '127.0.0.1';
async function start() {
  const storageMode = process.env.DATA_STORE ?? 'local';
  if (!['local', 'postgres'].includes(storageMode)) throw new Error('DATA_STORE deve ser local ou postgres.');
  const store = storageMode === 'postgres' ? new PostgresStore() : null;
  if (store) {
    const seedPath = process.env.HUBS_FILE ?? 'data/hubs/hubs.json';
    const hubs = JSON.parse(await readFile(seedPath, 'utf8'));
    await store.initialize({ hubs });
  }
  const app = await createApp({ mlUrl, timeoutMs, store });
  const server = app.listen(port, host, () => {
    console.log(`LogiPredict API em http://${host}:${port}`);
  });

  // Desligamento gracioso: fecha o servidor e sai em até 10 segundos.
  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.on(signal, () => {
      server.close(async () => {
        if (store) await store.close();
        process.exit(0);
      });
      setTimeout(() => process.exit(1), 10000).unref();
    });
  }
}

start().catch((err) => {
  console.error('Falha ao iniciar o servidor:', err);
  process.exit(1);
});
