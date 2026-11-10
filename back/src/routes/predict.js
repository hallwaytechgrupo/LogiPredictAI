import express from 'express';
import { readFile } from 'node:fs/promises';
import { classifyRisk, validateRiskInput, validateRiskReference } from '../risk.js';

export function createPredictRouter({ referenceFile } = {}) {
  const router = express.Router();
  const filename = referenceFile ?? process.env.PREDICT_REFERENCE_FILE ??
    new URL('../data/predict-reference.json', import.meta.url);
  let referencePromise;

  router.post('/', async (req, res) => {
    if (!req.is('application/json')) {
      return res.status(415).json({ error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Envie application/json.' });
    }
    const details = validateRiskInput(req.body);
    if (details.length) return res.status(422).json({ error: 'VALIDATION_ERROR', details });
    try {
      referencePromise ??= readFile(filename, 'utf8')
        .then((content) => validateRiskReference(JSON.parse(content)));
      const reference = await referencePromise;
      return res.json(classifyRisk(req.body, reference));
    } catch {
      referencePromise = undefined;
      return res.status(503).json({
        error: 'RISK_REFERENCE_UNAVAILABLE',
        message: 'Referência histórica indisponível. Gere o arquivo com logipredict.build_risk_reference.',
      });
    }
  });

  return router;
}
