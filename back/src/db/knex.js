import knex from 'knex';

const config = {
  client: 'pg',
  connection: {
    host: process.env.DB_HOST || 'localhost',
    database: process.env.DB_NAME || 'logipredict',
    user: process.env.DB_USER || 'logipredict',
    password: process.env.DB_PASSWORD || 'logipredict_secret',
    port: parseInt(process.env.DB_PORT, 10) || 5432,
  },
  pool: {
    min: 2,
    max: 10,
  },
  migrations: {
    directory: './src/db/migrations',
  },
  seeds: {
    directory: './src/db/seeds',
  },
  log: {
    warn(message) {
      if (message.code === '3D000') {
        // Ignore "database does not exist" during initial startup
        return;
      }
      console.warn('[knex:warn]', message);
    },
    error(message) {
      if (message.code === '3D000' || message.code === 'ECONNREFUSED') {
        // Ignore connection refused during startup
        return;
      }
      console.error('[knex:error]', message);
    },
  },
};

let instance;

export function getKnex() {
  if (!instance) {
    instance = knex(config);
  }
  return instance;
}

export function destroyKnex() {
  if (instance) {
    instance.destroy();
    instance = null;
  }
}

export default getKnex;
