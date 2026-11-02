import test, { afterEach, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';

let directory;
let hubsFile;
let server;
let baseUrl;

test('candidate API keeps blank cities pending and activates a candidate after review', async (t) => {
  directory = await mkdtemp(path.join(os.tmpdir(), 'logipredict-hubs-'));
  hubsFile = path.join(directory, 'hubs.json');
  await writeFile(hubsFile, '[]');
  server = createApp({ hubsFile }).listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    await rm(directory, { recursive: true, force: true });
  });

  const candidateResponse = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'OSM-relation-19997533',
      name: 'Candidato OSM',
      city: '',
      state: 'SP',
      validationStatus: 'PENDENTE_VALIDACAO',
      latitude: -23.5,
      longitude: -46.6,
      osmId: 'relation/19997533',
    }),
  });
  assert.equal(candidateResponse.status, 201);
  const candidate = (await candidateResponse.json()).data;
  assert.equal(candidate.status, 'inactive');
  assert.equal(candidate.validationStatus, 'PENDENTE_VALIDACAO');
  assert.equal(candidate.osmId, 'relation/19997533');

  const invalidApproval = await fetch(`${baseUrl}/api/v1/hubs/${candidate.id}/validation`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ validationStatus: 'APROVADO' }),
  });
  assert.equal(invalidApproval.status, 422);

  const editResponse = await fetch(`${baseUrl}/api/v1/hubs/${candidate.id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: candidate.code, name: candidate.name, city: 'São Paulo', state: 'SP' }),
  });
  assert.equal(editResponse.status, 200);
  const approvedResponse = await fetch(`${baseUrl}/api/v1/hubs/${candidate.id}/validation`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ validationStatus: 'APROVADO' }),
  });
  assert.equal(approvedResponse.status, 200);
  const approved = (await approvedResponse.json()).data;
  assert.equal(approved.status, 'active');
  assert.equal(approved.validationStatus, 'APROVADO');
  assert.equal(approved.latitude, -23.5);

  const listResponse = await fetch(`${baseUrl}/api/v1/hubs`);
  assert.equal(listResponse.status, 200);
  const listed = (await listResponse.json()).data;
  const listedCandidate = listed.find((hub) => hub.id === candidate.id);
  assert.equal(listedCandidate.latitude, -23.5);
  assert.equal(listedCandidate.longitude, -46.6);

  const noCoordinatesResponse = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'OSM-way-12345',
      name: 'Hub sem coordenadas',
      city: '',
      state: 'SP',
      validationStatus: 'PENDENTE_VALIDACAO',
    }),
  });
  assert.equal(noCoordinatesResponse.status, 201);
  const noCoordinatesHub = (await noCoordinatesResponse.json()).data;

  const invalidCoordinatesResponse = await fetch(`${baseUrl}/api/v1/hubs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code: 'OSM-way-12346',
      name: 'Hub com coordenadas inválidas',
      city: '',
      state: 'SP',
      validationStatus: 'PENDENTE_VALIDACAO',
      latitude: 91,
      longitude: 0,
    }),
  });
  assert.equal(invalidCoordinatesResponse.status, 422);

  const allHubsResponse = await fetch(`${baseUrl}/api/v1/hubs?status=all`);
  const allHubs = (await allHubsResponse.json()).data;
  const listedWithoutCoordinates = allHubs.find((hub) => hub.id === noCoordinatesHub.id);
  assert.equal(listedWithoutCoordinates.latitude, undefined);
  assert.equal(listedWithoutCoordinates.longitude, undefined);

  const stored = JSON.parse(await readFile(hubsFile, 'utf8'));
  assert.equal(stored.length, 2);
  assert.equal(stored[0].osmId, 'relation/19997533');
});
