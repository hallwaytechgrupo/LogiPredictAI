CREATE SCHEMA IF NOT EXISTS logipredict;

CREATE TABLE IF NOT EXISTS logipredict.collections (
    name text PRIMARY KEY CHECK (name IN ('hubs', 'orders', 'predictions')),
    revision bigint NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS logipredict.records (
    collection text NOT NULL REFERENCES logipredict.collections(name),
    id text NOT NULL,
    payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
    position bigint GENERATED ALWAYS AS IDENTITY,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (collection, id)
);

CREATE INDEX IF NOT EXISTS records_hub_idx
    ON logipredict.records (collection, (payload->>'hub_id'));
CREATE INDEX IF NOT EXISTS records_order_idx
    ON logipredict.records (collection, (payload->>'order_id'));

INSERT INTO logipredict.collections (name)
VALUES ('hubs'), ('orders'), ('predictions')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS logipredict.settings (
    name text PRIMARY KEY,
    value jsonb NOT NULL
);
