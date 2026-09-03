# BenchBase on CUBRID

CUBRID's fork of [`cmu-db/benchbase`](https://github.com/cmu-db/benchbase),
adding CUBRID 11.x as a benchmark target.

This file is the reference for the integration — what it covers, why the
defaults are what they are, and which paths the fork owns. For a build-and-run
summary, see [CUBRID Support](./README.md#cubrid-support) in the README.

**Contents**

- [Coverage](#coverage)
- [Prerequisites](#prerequisites)
- [Build](#build)
- [Run](#run)
- [Configuration](#configuration)
- [Isolation](#isolation)
- [Consistency conditions](#consistency-conditions)
- [Dialect files](#dialect-files)
- [Where the sysbench templates live](#where-the-sysbench-templates-live)
- [Fork allowlist and rebase hygiene](#fork-allowlist-and-rebase-hygiene)

## Coverage

| Benchmark | Status | CUBRID-specific files |
|-----------|--------|-----------------------|
| TPC-C | Ready | `src/main/resources/benchmarks/tpcc/ddl-cubrid.sql`, `config/cubrid/sample_tpcc_config.xml` |
| TPC-H | DDL and dialect ready; no sample config shipped yet | `src/main/resources/benchmarks/tpch/ddl-cubrid.sql`, `src/main/resources/benchmarks/tpch/dialect-cubrid.xml` |
| sysbench OLTP clone | Ready, through upstream's `templated` benchmark | `config/cubrid/sysbench_templated_config.xml`, `config/cubrid/sysbench_templates.xml` |

Running TPC-H today means writing a config XML modelled on
`config/cubrid/sample_tpcc_config.xml` — the schema and the query overrides are
already in place, only the workload descriptor is missing.

## Prerequisites

- A **CUBRID 11.x server** with the target database created and its broker
  reachable at the host and port named in your config XML. The shipped TPC-C
  sample expects `demodb` on port 33000; the sysbench sample expects `sbench`
  on port 35000.
- **Java 23** and **Maven** (or the bundled `./mvnw`).
- The **CUBRID JDBC jar** in your local Maven repository. CUBRID does not
  publish to Maven Central, so the `cubrid:cubrid-jdbc` coordinate used by the
  `cubrid` profile has to be satisfied locally:

  ```bash
  ./scripts/install-cubrid-jdbc.sh                  # auto-detects $CUBRID/jdbc/cubrid-jdbc-*.jar
  ./scripts/install-cubrid-jdbc.sh /path/to/cubrid-jdbc-11.3.2.0058.jar
  ```

  The script is idempotent: re-running it with the same jar is a no-op.

## Build

```bash
./scripts/install-cubrid-jdbc.sh      # one-time, per jar version
./mvnw clean package -P cubrid -DskipTests
```

This produces `target/benchbase-cubrid.tgz` (and `.zip`). Unpack it before
running — BenchBase reads `config/` and its dependencies relative to the
expanded distribution, and running the jar outside that layout fails with
`java.lang.NoClassDefFoundError`:

```bash
tar xvzf target/benchbase-cubrid.tgz -C target/
cd target/benchbase-cubrid
```

## Run

TPC-C, full cycle:

```bash
java -jar benchbase.jar -b tpcc \
    -c config/cubrid/sample_tpcc_config.xml \
    --create=true --load=true --execute=true
```

Each phase can also run on its own, which is the usual shape when iterating on
a workload against an already-loaded database:

```bash
java -jar benchbase.jar -b tpcc -c config/cubrid/sample_tpcc_config.xml --create=true
java -jar benchbase.jar -b tpcc -c config/cubrid/sample_tpcc_config.xml --load=true
java -jar benchbase.jar -b tpcc -c config/cubrid/sample_tpcc_config.xml --execute=true
```

The sysbench clone runs through upstream's `templated` plugin, which has no
loader — the table has to exist and be populated first. The DDL and the
expected row range are in a comment at the top of the config file:

```bash
java -jar benchbase.jar -b templated \
    -c config/cubrid/sysbench_templated_config.xml --execute=true
```

Results (tpmC, CSV, JSON) land in `results/`.

## Configuration

`config/cubrid/sample_tpcc_config.xml` is the starting point:

| Parameter | Default | Notes |
|---------------|--------------------------------------|--------------------------------------|
| `type` | `CUBRID` | Selects `ddl-cubrid.sql` and, where present, `dialect-cubrid.xml` |
| `driver` | `cubrid.jdbc.driver.CUBRIDDriver` | |
| `url` | `jdbc:cubrid:localhost:33000:demodb:::` | Change host, port, and database as needed |
| `username` | `dba` | CUBRID default DBA account |
| `password` | (empty) | CUBRID `dba` default is an empty password |
| `scalefactor` | `1` | Number of TPC-C warehouses |
| `terminals` | `1` | Concurrent virtual users |
| `isolation` | `TRANSACTION_READ_COMMITTED` | See [Isolation](#isolation) |

## Isolation

READ COMMITTED is the shipped default, chosen empirically rather than on
principle. The load phase under REPEATABLE READ on CUBRID 11.5 at scale factor 1
was markedly slower than under READ COMMITTED during integration, and the READ
COMMITTED load passed all four TPC-C §3.3.2 consistency conditions with zero
violations.

That is a single observation, not a probe. A proper comparison — READ COMMITTED
against REPEATABLE READ against SERIALIZABLE, repeated, gated on a numeric
consistency check — has not been run. Treat the default as provisional and
update `<isolation>` here if a real probe settles on a different level.

## Consistency conditions

After `--load=true`, verify TPC-C §3.3.2 conditions 1–4. Every query must
report `violations: 0`; anything else means the load did not produce a
spec-compliant dataset:

```bash
csql -C -u dba demodb@localhost -i scripts/tpcc-consistency-conditions.sql
```

Equivalents for cross-engine comparison runs ship alongside it —
`scripts/tpcc-consistency-conditions-pg.sql` and
`scripts/tpcc-consistency-conditions-mysql.sql`, paired with
`config/postgres/harness_tpcc_config.xml` and
`config/mysql/harness_tpcc_config.xml`. They exist so a CUBRID number can be
read next to a PostgreSQL or MySQL number produced by an identically shaped run.

## Dialect files

**TPC-C ships none, on purpose.** BenchBase validates dialect files against
`dialect.xsd`, which requires every `<dialect>` element to contain at least one
`<procedure>` child. CUBRID's SQL is ANSI-compatible with the default BenchBase
TPC-C statements, so there is nothing to override: an empty-body
`dialect-cubrid.xml` would fail XSD validation at load time, and one padded with
dummy procedures would be ornamental. This matches upstream, where
`dialect-postgres.xml` and `dialect-mysql.xml` are likewise absent and only
engines needing genuine overrides (`db2`, `monetdb`, `oracle`, `phoenix`,
`singlestore`, `sqlite`, `sqlserver`, `timesten`) ship one.

The CUBRID-specific TPC-C adjustments live in `ddl-cubrid.sql` instead:

- `DROP TABLE ... CASCADE CONSTRAINTS`, Oracle-style, which CUBRID requires.
- `new_order` declares its primary key before its foreign key, so CUBRID does
  not reject the second index when the FK and PK cover identical columns.

**TPC-H ships one.** `benchmarks/tpch/dialect-cubrid.xml` overrides 11 of the 22
queries (Q1, Q3, Q4, Q5, Q6, Q10, Q11, Q12, Q14, Q15, Q20), chiefly because the
generic stream uses `INTERVAL`, which CUBRID's parser rejects. Without the file
the stream fails at Q1 with `Syntax error: unexpected 'INTERVAL'`. The XSD
constraint above stops mattering the moment even one query needs an override,
which is exactly the condition for adding the file.

## Where the sysbench templates live

`config/cubrid/sysbench_templated_config.xml` drives a sysbench OLTP clone
through upstream's `TemplatedBenchmark`, and its query templates sit beside it
in `config/cubrid/sysbench_templates.xml` rather than in `data/templated/`,
where upstream keeps `example.xml`.

`data/templated/` is upstream's directory, and `sysbench.xml` is a name upstream
could plausibly use itself — a file there would widen the fork's conflict
surface for no gain. `query_templates_file` accepts any path, so nothing is lost
by keeping the templates with the fork's other CUBRID files.

The templates are written against one specific table — `sbtest1` with ids
1..100000 — and the ranges inside them say so. Changing the row count means
changing the templates too.

## Fork allowlist and rebase hygiene

Three upstream source files are modified, `README.md` gains two additive blocks,
and everything else is a new file. No other path is touched.

```
src/main/java/com/oltpbenchmark/types/DatabaseType.java   (one enum row added)
src/main/java/com/oltpbenchmark/util/SQLUtil.java         (getSchema() fallback -- see below)
pom.xml                                                   (one <profile id="cubrid"> block)
README.md                                                 (fork banner + CUBRID Support section)
CUBRID.md                                                 (this file)
src/main/resources/benchmarks/tpcc/ddl-cubrid.sql         (new)
src/main/resources/benchmarks/tpch/ddl-cubrid.sql         (new)
src/main/resources/benchmarks/tpch/dialect-cubrid.xml     (new)
config/cubrid/                                            (new directory)
config/postgres/harness_tpcc_config.xml                   (new -- cross-engine comparison)
config/mysql/harness_tpcc_config.xml                      (new -- cross-engine comparison)
scripts/install-cubrid-jdbc.sh                            (new)
scripts/tpcc-consistency-conditions.sql                   (new)
scripts/tpcc-consistency-conditions-pg.sql                (new)
scripts/tpcc-consistency-conditions-mysql.sql             (new)
data/templated/                                           (untouched -- see above)
```

Verify the allowlist against reality with:

```bash
git diff --name-only "$(git merge-base upstream/main HEAD)" HEAD
```

When rebasing onto upstream:

1. The `DatabaseType.java` enum row is a pure addition — no conflict expected
   unless upstream adds entries in the same region of the list.
2. The `pom.xml` profile block is a pure addition between the `postgres` and
   `mysql` profiles — no conflict expected unless upstream restructures
   profiles.
3. `README.md` conflicts only if upstream edits the same two regions: the
   masthead and the profile list under "How to Build".
4. Everything else is a new file — no conflict expected.

### `SQLUtil.java` — the one upstream behaviour this fork changes

This change is written to be upstreamed rather than carried: it names no engine.

`SQLUtil.getCatalogDirect()` called `connection.getSchema()` unconditionally.
That method is JDBC 4.1 and optional in practice — a driver for a DBMS with no
schema concept may reasonably throw rather than invent an answer, and CUBRID's
does. Because `refreshCatalog()` runs on every invocation, this took down
**every** benchmark on CUBRID before any SQL was issued:

```
java.sql.SQLException: java.lang.UnsupportedOperationException
    at cubrid.jdbc.driver.CUBRIDConnection.getSchema(CUBRIDConnection.java:1076)
    at com.oltpbenchmark.util.SQLUtil.getCatalogDirect(SQLUtil.java:575)
    at com.oltpbenchmark.api.BenchmarkModule.refreshCatalog(BenchmarkModule.java:221)
```

The fix reads the schema through `getSchemaOrNull()`, which returns null when
the driver does not implement it. A null schema pattern means "do not filter by
schema" to `DatabaseMetaData` — for a DBMS without JDBC schemas that is the
correct query, not a degraded one, which is why the fix carries no CUBRID branch
and should apply upstream unchanged.

**Upstream status: not yet filed.** File it against `cmu-db/benchbase` and
replace this note with the outcome.
