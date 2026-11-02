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
import { createApp } from './app.js';

const port = Number(process.env.PORT ?? 3001);
const timeoutMs = Number(process.env.ML_TIMEOUT_MS ?? 10000);
const mlUrl = new URL(process.env.ML_URL ?? 'http://127.0.0.1:8000');
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT inválida.');
if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 120000) throw new Error('ML_TIMEOUT_MS inválido.');
if (!['http:', 'https:'].includes(mlUrl.protocol)) throw new Error('ML_URL deve usar HTTP ou HTTPS.');
const host = process.env.HOST ?? '127.0.0.1';
const server = createApp({ mlUrl, timeoutMs }).listen(port, host, () => {
  console.log(`LogiPredict API em http://${host}:${port}`);
});

// Desligamento gracioso: fecha o servidor e sai em até 10 segundos.
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10000).unref();
  });
}