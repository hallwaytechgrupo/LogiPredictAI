/** Persistência remota por registro, preservando o contrato JSON da aplicação. */
import { createHash, randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import pg from 'pg';
import { cloudRequest, collectionVersions } from './cloud-context.js';

const COLLECTIONS = new Set(['hubs', 'orders', 'predictions']);

export class StorageConflict extends Error {
  constructor() {
    super('Os dados foram atualizados em outra sessão. Recarregue e tente novamente.');
    this.code = 'STORAGE_CONFLICT';
    this.status = 409;
  }
}

function collectionName(value) {
  if (!COLLECTIONS.has(value)) throw new Error('Coleção de armazenamento inválida.');
  return value;
}

function recordId(collection, value) {
  const id = collection === 'hubs' ? value.id
    : collection === 'orders' ? value.order_id
      : value.prediction_id ?? value.id;
  if (id != null && String(id).trim()) return String(id);
  if (collection === 'predictions') {
    return createHash('sha256').update(JSON.stringify(value)).digest('hex');
  }
  throw new Error(`Registro de ${collection} sem identificador.`);
}

export function databaseOptions(connectionString) {
  if (!connectionString) throw new Error('DATABASE_URL é obrigatória com DATA_STORE=postgres.');
  const url = new URL(connectionString);
  if (!['postgres:', 'postgresql:'].includes(url.protocol)) {
    throw new Error('DATABASE_URL deve ser uma conexão PostgreSQL.');
  }
  const local = ['localhost', '127.0.0.1', '::1', '[::1]'].includes(url.hostname);
  // Em conexões externas, exige TLS com validação do certificado e do servidor.
  if (!local) url.searchParams.set('sslmode', 'verify-full');
  return {
    connectionString: url.toString(),
    max: 3,
    idleTimeoutMillis: 10000,
    connectionTimeoutMillis: 10000,
    statement_timeout: 15000,
  };
}

export class PostgresStore {
  constructor({ connectionString = process.env.DATABASE_URL, pool } = {}) {
    this.pool = pool ?? new pg.Pool(databaseOptions(connectionString));
    this.pool.on('error', () => console.error('[DB] A conexão ociosa foi encerrada.'));
  }

  async initialize({ hubs = [] } = {}) {
    const schema = await readFile(new URL('./cloud-schema.sql', import.meta.url), 'utf8');
    await this.transaction(async (client) => {
      // Duas instâncias podem iniciar juntas; a migração e a carga inicial são únicas.
      await client.query("SELECT pg_advisory_xact_lock(hashtext('logipredict-bootstrap'))");
      await client.query(schema);
      const first = await client.query(
        "INSERT INTO logipredict.settings (name, value) VALUES ('initialized', 'true') ON CONFLICT DO NOTHING RETURNING name",
      );
      if (first.rowCount) await this.putRecords(client, 'hubs', hubs);
    });
  }

  run(operation) {
    return cloudRequest(this, operation);
  }

  async health() {
    await this.pool.query('SELECT 1');
  }

  async transaction(operation) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await operation(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  async read(collection) {
    collectionName(collection);
    // Dados e revisão são lidos no mesmo snapshot do PostgreSQL.
    const { rows } = await this.pool.query(`
      SELECT c.revision, COALESCE(
        jsonb_agg(r.payload ORDER BY r.position) FILTER (WHERE r.id IS NOT NULL), '[]'
      ) AS records
      FROM logipredict.collections c
      LEFT JOIN logipredict.records r ON r.collection = c.name
      WHERE c.name = $1 GROUP BY c.name, c.revision`, [collection]);
    if (!rows.length) throw new Error('Armazenamento remoto não inicializado.');
    collectionVersions()?.set(collection, String(rows[0].revision));
    return rows[0].records;
  }

  async putRecords(client, collection, records) {
    const items = records.map((value) => ({ id: recordId(collection, value), payload: value }));
    if (new Set(items.map((item) => item.id)).size !== items.length) {
      throw new Error(`Identificadores duplicados em ${collection}.`);
    }
    if (!items.length) return;
    await client.query(`
      INSERT INTO logipredict.records (collection, id, payload)
      SELECT $1, entry.id, entry.payload
      FROM jsonb_to_recordset($2::jsonb) AS entry(id text, payload jsonb)
      ON CONFLICT (collection, id) DO UPDATE
      SET payload = EXCLUDED.payload, updated_at = now()`, [collection, JSON.stringify(items)]);
  }

  async replace(collection, records) {
    collectionName(collection);
    if (!Array.isArray(records)) throw new Error('A coleção deve ser uma lista.');
    const versions = collectionVersions();
    const expected = versions?.get(collection);
    if (expected == null) throw new Error('Leia a coleção antes de substituí-la.');
    const revision = await this.transaction(async (client) => {
      const updated = await client.query(`
        UPDATE logipredict.collections SET revision = revision + 1
        WHERE name = $1 AND revision = $2 RETURNING revision`, [collection, expected]);
      if (!updated.rowCount) throw new StorageConflict();
      await this.putRecords(client, collection, records);
      await client.query(
        'DELETE FROM logipredict.records WHERE collection = $1 AND NOT (id = ANY($2::text[]))',
        [collection, records.map((record) => recordId(collection, record))],
      );
      return String(updated.rows[0].revision);
    });
    versions.set(collection, revision);
  }

  async appendPredictions(records) {
    if (!records.length) return;
    await this.transaction(async (client) => {
      await client.query("UPDATE logipredict.collections SET revision = revision + 1 WHERE name = 'predictions'");
      await this.putRecords(client, 'predictions', records.map((record) => ({
        ...record, prediction_id: record.prediction_id ?? record.id ?? randomUUID(),
      })));
    });
  }

  async close() {
    await this.pool.end();
  }
}
