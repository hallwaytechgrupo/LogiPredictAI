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
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10000).unref();
  });
}
