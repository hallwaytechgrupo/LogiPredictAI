import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';

test('resolves CEP prefixes from the training geolocation source and returns the longest seller route', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-geo-'));
  const geolocationFile = path.join(directory, 'geolocation.csv');
  await writeFile(geolocationFile, [
    'geolocation_zip_code_prefix,geolocation_lat,geolocation_lng,geolocation_city,geolocation_state',
    '01000,-23.6,-46.6,"sao paulo, centro",SP',
    '01000,-23.4,-46.4,"sao paulo, centro",SP',
    '01001,-23.7,-46.2,sao paulo,SP',
    '02000,-22.9,-43.2,rio de janeiro,RJ',
    '',
  ].join('\n'));
  const server = createApp({ geolocationFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  t.after(async () => {
    await new Promise((resolve, reject) =>
      server.close((error) => error ? reject(error) : resolve()),
    );
    await rm(directory, { recursive: true, force: true });
  });
  const baseUrl = 'http://127.0.0.1:' + server.address().port;

  const resolved = await fetch(baseUrl + '/api/v1/geolocation/route', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      origin_ceps: ['01000-001', '01000-002'],
      destination_cep: '02000-001',
    }),
  });
  assert.equal(resolved.status, 200);
  const route = (await resolved.json()).data;
  assert.equal(route.origins.length, 2);
  assert.equal(route.origins[0].latitude, -23.5);
  assert.equal(route.origins[0].longitude, -46.5);
  assert.equal(route.origins[0].city, 'sao paulo, centro');
  assert.equal(route.destination.state, 'RJ');
  assert.equal(route.seller_state, 'SP');
  assert.ok(route.distance_km > 300 && route.distance_km < 400);

  const sameStateRoute = await fetch(baseUrl + '/api/v1/geolocation/route', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      origin_ceps: ['01000-001'],
      destination_cep: '01001-001',
    }),
  });
  const sameState = (await sameStateRoute.json()).data;
  assert.equal(sameState.seller_state, 'SP');
  assert.equal(sameState.customer_state, 'SP');
  assert.ok(sameState.distance_km > 0);

  const invalidCep = await fetch(baseUrl + '/api/v1/geolocation/route', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      origin_ceps: ['0100A-001'],
      destination_cep: '02000-001',
    }),
  });
  assert.equal(invalidCep.status, 422);

  const absentPrefix = await fetch(baseUrl + '/api/v1/geolocation/route', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      origin_ceps: ['99999-001'],
      destination_cep: '02000-001',
    }),
  });
  assert.equal(absentPrefix.status, 404);
});

test('reports the geolocation source as unavailable rather than using a fallback', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-geo-missing-'));
  const server = createApp({
    geolocationFile: path.join(directory, 'missing.csv'),
  }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  t.after(async () => {
    await new Promise((resolve, reject) =>
      server.close((error) => error ? reject(error) : resolve()),
    );
    await rm(directory, { recursive: true, force: true });
  });
  const response = await fetch(
    'http://127.0.0.1:' + server.address().port + '/api/v1/geolocation/route',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        origin_ceps: ['01000-001'],
        destination_cep: '02000-001',
      }),
    },
  );
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, 'GEOLOCATION_SOURCE_UNAVAILABLE');
});
