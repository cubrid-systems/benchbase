-- ddl-cubrid.sql
-- OT-Metrics schema for CUBRID 11.x.
--
-- Derived from ddl-generic.sql with one change: observations.value is quoted.
-- `value` is a CUBRID reserved word, rejected in DDL and in queries alike:
--
--     CREATE TABLE t (id INT PRIMARY KEY, value INT)
--       Syntax error: unexpected 'value'
--     SELECT id FROM t ORDER BY value ASC
--       Syntax error: unexpected 'value'
--
-- Bracket-quoting satisfies both. Only the schema needs it here, and no
-- dialect-cubrid.xml is required, because no SQL this benchmark issues names
-- the column: GetSessionRange, its only procedure, selects with `SELECT *`,
-- and OTMetricsLoader builds its INSERT through SQLUtil.getInsertSQL, which
-- omits column names for CUBRID. value_type in the types table is a different
-- identifier and is left as it is.

DROP TABLE IF EXISTS observations;
DROP TABLE IF exists types;
DROP TABLE IF EXISTS sessions;
DROP TABLE IF exists sources;

CREATE TABLE sources (
    id INTEGER NOT NULL,
    name VARCHAR(128) NOT NULL UNIQUE,
    comment varchar(256) DEFAULT NULL,
    created_time TIMESTAMP NOT NULL,
    PRIMARY KEY (id)
);

CREATE TABLE types (
    id INTEGER NOT NULL,
    category INTEGER NOT NULL,
    value_type INTEGER NOT NULL,
    name VARCHAR(64) NOT NULL,
    comment varchar(256) DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE (category, name)
);

CREATE TABLE sessions (
    id INTEGER NOT NULL,
    source_id INTEGER NOT NULL REFERENCES sources (id),
    agent VARCHAR(32) NOT NULL,
    created_time TIMESTAMP NOT NULL,
    PRIMARY KEY (id)
);

CREATE TABLE observations (
  source_id INTEGER NOT NULL REFERENCES sources (id),
  session_id INTEGER NOT NULL REFERENCES sessions (id),
  type_id INTEGER NOT NULL REFERENCES types (id),
  [value] DOUBLE PRECISION NOT NULL,
  created_time TIMESTAMP NOT NULL
);
CREATE INDEX idx_observations_source_session ON observations (source_id, session_id, type_id);