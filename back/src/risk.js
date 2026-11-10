/** Regras BE-03 sobre estatísticas históricas, geradas offline a partir da Olist. */
export function validateRiskInput(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return [{ field: 'body', message: 'Envie um objeto JSON.' }];
  }
  const errors = [];
  const fields = ['total_weight_g', 'distance_km', 'remaining_days'];
  for (const field of Object.keys(body)) {
    if (!fields.includes(field)) errors.push({ field, message: 'Campo desconhecido.' });
  }
  for (const field of fields) {
    if (typeof body[field] !== 'number' || !Number.isFinite(body[field])) {
      errors.push({ field, message: 'Informe um número finito.' });
    }
  }
  if (typeof body.total_weight_g === 'number' && body.total_weight_g <= 0) {
    errors.push({ field: 'total_weight_g', message: 'Informe peso maior que zero em gramas.' });
  }
  if (typeof body.distance_km === 'number' && (body.distance_km < 0 || body.distance_km > 20050)) {
    errors.push({ field: 'distance_km', message: 'Informe distância entre 0 e 20050 km.' });
  }
  if (typeof body.remaining_days === 'number' && (!Number.isInteger(body.remaining_days) || body.remaining_days < 0)) {
    errors.push({ field: 'remaining_days', message: 'Informe um inteiro não negativo em dias de calendário.' });
  }
  return errors;
}

export function validateRiskReference(reference) {
  const policy = reference?.policy;
  const validBounds = (values) => Array.isArray(values) && values.length > 0 &&
    values.every((value, index) => Number.isFinite(value) && value > 0 && (index === 0 || value > values[index - 1]));
  const validStats = (stats) => stats && Number.isInteger(stats.sample_size) && stats.sample_size > 0 &&
    Number.isInteger(stats.transit_days_p50) && stats.transit_days_p50 >= 0 &&
    Number.isInteger(stats.transit_days_p90) && stats.transit_days_p90 >= stats.transit_days_p50 &&
    Number.isFinite(stats.weight_g_min) && stats.weight_g_min > 0 &&
    Number.isFinite(stats.weight_g_max) && stats.weight_g_max >= stats.weight_g_min &&
    Number.isFinite(stats.distance_km_min) && stats.distance_km_min >= 0 &&
    Number.isFinite(stats.distance_km_max) && stats.distance_km_max >= stats.distance_km_min;
  if (reference?.schema_version !== 1 || reference.source !== 'olist' || reference.synthetic !== false ||
      reference.method !== 'historical_rules' || typeof reference.rules_version !== 'string' ||
      !reference.rules_version || !reference.period || !policy ||
      !validBounds(policy.distance_bounds_km) || !validBounds(policy.weight_bounds_g) ||
      !Number.isInteger(policy.min_sample_size) || policy.min_sample_size < 1 ||
      !validStats(reference.global) || reference.global.sample_size < policy.min_sample_size ||
      !Array.isArray(reference.groups) || !reference.groups.every(validStats) ||
      !Array.isArray(reference.distance_groups) || !reference.distance_groups.every(validStats)) {
    throw new Error('Referência histórica inválida.');
  }
  return reference;
}

function bandIndex(value, bounds) {
  const index = bounds.findIndex((upper) => value <= upper);
  return index === -1 ? bounds.length : index;
}

export function classifyRisk(input, reference) {
  const policy = reference.policy;
  const distanceBand = bandIndex(input.distance_km, policy.distance_bounds_km);
  const weightBand = bandIndex(input.total_weight_g, policy.weight_bounds_g);
  const candidates = [
    { level: 'distance_weight', stats: reference.groups.find((group) => group.distance_band === distanceBand && group.weight_band === weightBand) },
    { level: 'distance', stats: reference.distance_groups.find((group) => group.distance_band === distanceBand) },
    { level: 'global', stats: reference.global },
  ];
  const { level, stats } = candidates.find(({ stats }) => stats?.sample_size >= policy.min_sample_size);
  let risk = 'Baixo';
  let rule = 'remaining_days >= transit_days_p90';
  if (input.remaining_days < stats.transit_days_p50) {
    risk = 'Alto';
    rule = 'remaining_days < transit_days_p50';
  } else if (input.remaining_days < stats.transit_days_p90) {
    risk = 'Médio';
    rule = 'transit_days_p50 <= remaining_days < transit_days_p90';
  }
  const warnings = [
    'Referência histórica da Olist de 2016–2018. Validar com a operação atual.',
    'Classificação demonstrativa por percentis históricos, sem probabilidade calibrada ou validação de desempenho.',
    'A base agrega pedidos e usa distância em linha reta entre vendedor e cliente.',
  ];
  if (level !== 'distance_weight') {
    warnings.push('Amostra insuficiente na faixa de peso e distância. Foi utilizada uma referência mais abrangente.');
  }
  if (input.total_weight_g < stats.weight_g_min || input.total_weight_g > stats.weight_g_max ||
      input.distance_km < stats.distance_km_min || input.distance_km > stats.distance_km_max) {
    warnings.push('Peso ou distância fora dos valores observados na referência selecionada. Resultado extrapolado.');
  }
  return {
    risk,
    method: reference.method,
    rules_version: reference.rules_version,
    source: reference.source,
    synthetic: reference.synthetic,
    input,
    rule,
    reference: {
      level,
      distance_band: distanceBand,
      weight_band: weightBand,
      ...stats,
      period: reference.period,
      observed_before: reference.observed_before,
      dataset_url: reference.dataset_url,
    },
    warnings,
  };
}
