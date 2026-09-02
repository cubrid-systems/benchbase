# BenchBase — CUBRID Integration

Internal fork of BenchBase enabling CUBRID 11.x as a TPC-C benchmark target.
Phase 1 deliverable per the consensus plan at
`/data/cub_sys/.omc/plans/cubrid-benchmarking-phase1.md`.

## Prerequisites

- **CUBRID 11.x server** running with `demodb` created (or your target DB).
  Broker must be listening on port 33000 (default; configurable in the config
  XML). See `scripts/cubrid_lifecycle.sh` in the parent harness for setup.
- **CUBRID JDBC jar** installed into the local Maven repository. Run:
  ```bash
  bash scripts/install-cubrid-jdbc.sh
  ```
  This script auto-detects the jar from `$CUBRID/jdbc/cubrid-jdbc-*.jar` (the
  installed CUBRID ships it). Pass an explicit path as the first argument if
  needed:
  ```bash
  bash scripts/install-cubrid-jdbc.sh /path/to/cubrid-jdbc-11.3.2.0058.jar
  ```
- **Java 23** and **Maven 3.x** on PATH.

## Build

```bash
# 1. Install the CUBRID JDBC jar into the local Maven repo (one-time)
bash scripts/install-cubrid-jdbc.sh

# 2. Package BenchBase with the CUBRID profile
mvn -P cubrid package -DskipTests
```

The resulting artifact is `target/benchbase-cubrid.tgz`. Unpack it:

```bash
tar -xzf target/benchbase-cubrid.tgz -C target/
```

## Run

Full create + load + execute cycle against CUBRID:

```bash
java -jar target/benchbase-cubrid/benchbase.jar \
    -b tpcc \
    -c config/cubrid/sample_tpcc_config.xml \
    --create=true \
    --load=true \
    --execute=true
```

Results (tpmC, CSV, JSON) are written to the `results/` directory.

To run only schema creation, loading, or execution independently:

```bash
# Schema only
java -jar target/benchbase-cubrid/benchbase.jar -b tpcc \
    -c config/cubrid/sample_tpcc_config.xml --create=true

# Load only
java -jar target/benchbase-cubrid/benchbase.jar -b tpcc \
    -c config/cubrid/sample_tpcc_config.xml --load=true

# Execute only (after schema + load)
java -jar target/benchbase-cubrid/benchbase.jar -b tpcc \
    -c config/cubrid/sample_tpcc_config.xml --execute=true
```

## Configuration

Edit `config/cubrid/sample_tpcc_config.xml` to adjust:

| Parameter     | Default                              | Notes                                  |
|---------------|--------------------------------------|----------------------------------------|
| `url`         | `jdbc:cubrid:localhost:33000:demodb:::` | Change host/port/db as needed        |
| `username`    | `dba`                                | CUBRID default DBA account             |
| `password`    | (empty)                              | CUBRID dba default = empty password    |
| `scalefactor` | `1`                                  | Number of TPC-C warehouses             |
| `terminals`   | `1`                                  | Concurrent virtual users               |
| `isolation`   | `TRANSACTION_READ_COMMITTED`         | See isolation note below               |

## Isolation Note

READ_COMMITTED is the Phase 1 default, empirically selected. The load phase under
REPEATABLE_READ on CUBRID 11.5 at SF=1 was markedly slower than RC (observed
during integration). The load under RC passed all four TPC-C consistency
conditions (§3.3.2) with zero violations — see
`scripts/tpcc-consistency-conditions.sql` and the archived output in
`.omc/reports/benchbase-run-results/m3-consistency.out`.

The formal M0.5 empirical probe (RC vs REP_READ vs SERIALIZABLE × N reps ×
numeric consistency-gate) is deferred to Phase 2 per ADR-3 in the plan. Update
`<isolation>` here when the probe commits a different primary level.

## Consistency Conditions

After `--load=true`, verify TPC-C §3.3.2 conditions 1–4:

```bash
source /data/cub_sys/.cubrid.sh
csql -C -u dba demodb@localhost -i scripts/tpcc-consistency-conditions.sql
```

All four queries must report `violations: 0`. Any non-zero value indicates the
load did not produce a spec-compliant TPC-C dataset on CUBRID.

## Dialect files: none for TPC-C, one for TPC-H

**TPC-C needs no dialect.** BenchBase's JAXB-validated `dialect.xsd` requires
every `<dialect>` element to contain at least one `<procedure>` child. CUBRID's
SQL is ANSI-compatible with the default BenchBase TPC-C statements — no
overrides are needed. Shipping an empty-body `dialect-cubrid.xml` fails XSD
validation at load time; shipping a dialect file with dummy procedures would be
ornamental.

**TPC-H does.** `benchmarks/tpch/dialect-cubrid.xml` overrides 11 of the 22
queries (Q1, Q3, Q4, Q5, Q6, Q10, Q11, Q12, Q14, Q15, Q20), chiefly because the
generic stream uses `INTERVAL`, which CUBRID's parser rejects. The XSD
constraint above is satisfied the moment even one query needs an override, which
is exactly the condition ADR-0005 named for adding the file. Without it the
stream fails at Q1 with `Syntax error: unexpected 'INTERVAL'`.

The historical rationale for TPC-C is preserved below because it still holds
for that benchmark.

## Why There Is No TPC-C `dialect-cubrid.xml`

BenchBase's JAXB-validated `dialect.xsd` requires every `<dialect>` element to
contain at least one `<procedure>` child. CUBRID's SQL is ANSI-compatible with
the default BenchBase TPC-C statements — no overrides are needed. Shipping an
empty-body `dialect-cubrid.xml` fails XSD validation at load time; shipping a
dialect file with dummy procedures would be ornamental.

This matches how `dialect-postgres.xml` and `dialect-mysql.xml` are absent: only
databases that need genuine SQL overrides (`db2`, `monetdb`, `oracle`, `phoenix`,
`singlestore`, `sqlite`, `sqlserver`, `timesten`) ship dialect files.

The CUBRID-specific DDL details live instead in `ddl-cubrid.sql`:
- `DROP TABLE ... CASCADE CONSTRAINTS` (Oracle-style, required by CUBRID)
- `new_order` has PK declared before FK to prevent CUBRID's duplicate-index
  rejection when FK and PK cover identical column lists.

## Fork Allowlist (Rebase Hygiene)

All CUBRID-specific changes in this fork are confined to the following paths.
No other files are modified. See M7 in the plan for the formal allowlist check.

```
src/main/java/com/oltpbenchmark/types/DatabaseType.java   (one enum row added)
src/main/java/com/oltpbenchmark/util/SQLUtil.java         (getSchema() fallback — see below)
pom.xml                                                   (one <profile id="cubrid"> block)
src/main/resources/benchmarks/tpcc/ddl-cubrid.sql         (new)
src/main/resources/benchmarks/tpch/ddl-cubrid.sql         (new)
src/main/resources/benchmarks/tpch/dialect-cubrid.xml     (new)
config/cubrid/                                            (new directory)
data/templated/                                           (untouched -- see below)
scripts/install-cubrid-jdbc.sh                            (new)
scripts/tpcc-consistency-conditions.sql                   (new)
CUBRID.md                                                 (this file)
```

Note on the TPC-C dialect: `benchmarks/tpcc/dialect-cubrid.xml` does NOT exist —
see "Why There Is No TPC-C dialect-cubrid.xml" above. The spec's allowlist
included it by analogy with other dialect files, but the JAXB XSD constraint
makes the empty-overrides case a no-file case. The TPC-H one does exist and is
listed above.

### `SQLUtil.java` — the one upstream file this fork touches

ADR-0005 says to prefer upstreaming over widening the allowlist, and this change
is written to be upstreamed rather than kept: it names no engine.

`SQLUtil.getCatalogDirect()` called `connection.getSchema()` unconditionally.
That method is JDBC 4.1 and optional in practice — a driver for a DBMS with no
schema concept may reasonably throw instead of inventing an answer, and CUBRID's
does (`CUBRIDConnection.getSchema()` throws `UnsupportedOperationException`).
`refreshCatalog()` runs for every invocation, so this took down **every**
benchmark on CUBRID before any SQL was issued:

```
java.sql.SQLException: java.lang.UnsupportedOperationException
    at cubrid.jdbc.driver.CUBRIDConnection.getSchema(CUBRIDConnection.java:1076)
    at com.oltpbenchmark.util.SQLUtil.getCatalogDirect(SQLUtil.java:575)
    at com.oltpbenchmark.api.BenchmarkModule.refreshCatalog(BenchmarkModule.java:221)
```

The fix reads the schema through `getSchemaOrNull()`, which returns null when the
driver does not implement it. A null schema pattern means "do not filter by
schema" to `DatabaseMetaData` — for a DBMS without JDBC schemas that is the
correct query, not a degraded one, which is why the fix carries no CUBRID
branch and should apply upstream unchanged.

**Upstream status: not yet filed.** ADR-0005 asks for
`(upstream-rejected: <link>)` on an allowlist entry that upstream declined; this
one has not been offered yet, so it is carried as upstream-pending. File it
against `cmu-db/benchbase` and replace this note with the outcome.

### Why the sysbench templates live in `config/cubrid/`

`config/cubrid/sysbench_templated_config.xml` runs a sysbench OLTP clone through
upstream's `TemplatedBenchmark`, and its query templates sit beside it in
`config/cubrid/sysbench_templates.xml` rather than in `data/templated/`, where
upstream keeps `example.xml`.

`data/templated/` is upstream's directory. A file added there is outside the
allowlist above, and `sysbench.xml` is a name upstream could plausibly use
itself. `query_templates_file` takes any path, so nothing is lost by keeping the
file where this fork's other CUBRID files already are.

The templates are written against a specific table -- `sbtest1` with ids
1..100000 -- and the ranges in them say so. Templated benchmarks do not load, so
that table has to exist first; the config file carries the DDL in a comment.

When rebasing against upstream BenchBase:
1. The `DatabaseType.java` enum row is a pure addition — no conflict expected
   unless upstream adds entries in the same alphabetical region.
2. The `pom.xml` profile block is a pure addition between `postgres` and `mysql`
   profiles — no conflict expected unless upstream restructures profiles.
3. All other paths are new files — no conflict expected.
