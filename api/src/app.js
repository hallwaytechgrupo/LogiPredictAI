import express from 'express';
import helmet from 'helmet';

export function createApp({ mlUrl = 'http://127.0.0.1:8000', timeoutMs = 10000 } = {}) {
  const app = express();
  app.disable('x-powered-by');
  app.use(helmet());
  app.use(express.json({ limit: '32kb', strict: true }));

  function proxy(path, method = 'GET') {
    return async (req, res) => {
      if (method === 'POST' && !req.is('application/json')) {
        return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
      }
      try {
        const upstream = await fetch(new URL(path, mlUrl), {
          method,
          headers: { Accept: 'application/json', ...(method === 'POST' ? { 'Content-Type': 'application/json' } : {}) },
          ...(method === 'POST' ? { body: JSON.stringify(req.body ?? {}) } : {}),
          signal: AbortSignal.timeout(timeoutMs),
        });
        const payload = await upstream.json();
        if (upstream.status === 422) {
          // Não repassar os valores de entrada incluídos pelo Pydantic nos erros.
          const details = (payload.detail ?? []).map(({ loc, msg, type }) => ({ field: loc, message: msg, type }));
          return res.status(422).json({ error: 'VALIDATION_ERROR', details });
        }
        if (upstream.status === 503) {
          return res.status(503).json({ error: 'MODEL_UNAVAILABLE', message: 'Treine o modelo e reinicie o serviço Python.' });
        }
        if (!upstream.ok) {
          return res.status(502).json({ error: 'ML_ERROR', message: 'Falha no serviço de previsão.' });
        }
        return res.json(payload);
      } catch (error) {
        if (error instanceof SyntaxError) {
          return res.status(502).json({ error: 'ML_ERROR', message: 'Resposta inválida do serviço de previsão.' });
        }
        const timeout = error.name === 'TimeoutError' || error.name === 'AbortError';
        return res.status(timeout ? 504 : 503).json({
          error: timeout ? 'ML_TIMEOUT' : 'ML_UNAVAILABLE',
          message: timeout ? 'Tempo limite do serviço de previsão excedido.' : 'Serviço Python indisponível.',
        });
      }
    };
  }

  app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'logipredict-api', version: '0.1.0' }));
  app.get('/ready', proxy('/health'));
  app.get('/api/v1/model', proxy('/model'));
  app.get('/api/v1/analytics/states', proxy('/analytics/states'));
  app.post('/api/v1/predictions', proxy('/predict', 'POST'));
  app.use((_req, res) => res.status(404).json({ error: 'NOT_FOUND' }));
  app.use((error, _req, res, _next) => {
    if (error.type === 'entity.too.large') return res.status(413).json({ error: 'PAYLOAD_TOO_LARGE' });
    if (error.type === 'entity.parse.failed') return res.status(400).json({ error: 'INVALID_JSON' });
    return res.status(500).json({ error: 'INTERNAL_ERROR' });
  });
  return app;
}
