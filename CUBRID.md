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

Verified end to end against CUBRID 11.5 unless the table says otherwise: schema
created, data loaded, workload executed, no unexpected SQL errors. Everything
from `sibench` down was run on a release build of `develop`
(11.5.0.2513-5f3a30d); the rows above it were run earlier on a debug build.

| Benchmark | Transactions | CUBRID-specific files |
|---|---:|---|
| TPC-C | verified | `benchmarks/tpcc/ddl-cubrid.sql`, `config/cubrid/sample_tpcc_config.xml` |
| TPC-H | 22 of 22 queries | `benchmarks/tpch/ddl-cubrid.sql`, `benchmarks/tpch/dialect-cubrid.xml`, config |
| YCSB | 55,066 | config only |
| TATP | 17,226 | config only |
| SmallBank | 882 | config only |
| Voter | 4,491 | config only |
| SIBench | 15,397 | `benchmarks/sibench/ddl-cubrid.sql` + `dialect-cubrid.xml`, config |
| OT-Metrics | 50,735 | `benchmarks/otmetrics/ddl-cubrid.sql`, config |
| Twitter | 70,723 | `benchmarks/twitter/ddl-cubrid.sql`, config |
| SEATS | 7,394 | config only |
| AuctionMark | 8,831 | `benchmarks/auctionmark/ddl-cubrid.sql`, config |
| Epinions | 19,136 | config only |
| hyadapt | 16,059 | config only |
| NoOp | 15,001 | config only |
| ResourceStresser | 4 in 60s | config only -- see below |
| CH-benCHmark | schema only | `benchmarks/chbenchmark/ddl-cubrid.sql`; needs a `tpcc,chbenchmark` config |
| Wikipedia | blocked | `benchmarks/wikipedia/ddl-cubrid.sql`; schema loads, catalog read does not -- see below |
| sysbench OLTP clone | never run | `config/cubrid/sysbench_templated_config.xml`, `sysbench_templates.xml` |

ResourceStresser is not broken: its procedures are deliberately expensive, and
sixty seconds at one terminal completed four transactions with no SQL errors.
Give it minutes, not seconds.

### Wikipedia is blocked by the server, not by the schema

`ddl-cubrid.sql` creates all twelve tables, twice in a row. What fails is the
step after: `SQLUtil.getCatalogDirect ()` walks `DatabaseMetaData`, and once
enough tables are in the schema a call comes back as

    Empty component list in class.

That is `ER_OBJ_NO_COMPONENTS (-226)`, and CUBRID raises it at
`ER_WARNING_SEVERITY` from `db_get_superclasses ()`, `db_get_subclasses ()` and
`db_get_attributes ()` in `src/compat/db_info.c` -- whenever a class has no
superclasses, no subclasses, or no attributes of the kind asked for. An ordinary
table with no inheritance satisfies the first two every time, so the warning is
set constantly; it only becomes visible when a later call reports the lingering
error state.

The shape of it, measured:

- Not table-specific: `getImportedKeys` on the same table sixty times in a row
  is fine.
- Cumulative across *different* tables: the 27th call fails, deterministically.
- Not the driver: 11.3.2.0058 and 11.4.0.0075 behave identically.
- Reproduces on a release build of `develop`, so it is not feature-branch
  fallout.

This is why the benchmarks with few tables were never affected -- TPC-C has
nine, TPC-H eight, YCSB one -- and Wikipedia, at twelve plus whatever else is in
the schema, is.

## Prerequisites

- A **CUBRID 11.x server** with the target database created and its broker
  reachable at the host and port named in your config XML. The shipped TPC-C
  sample expects `demodb` on port 33000, the YCSB sample a `ycsb` database on
  the same port, and the sysbench sample `sbench` on port 35000.
- **Java 23** and **Maven** (or the bundled `./mvnw`). A JDK 21 toolchain also
  works -- see [Building on a JDK older than 23](#building-on-a-jdk-older-than-23).
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

### Building on a JDK older than 23

Upstream moved the project to Java 23. The CUBRID integration adds no Java, and
the tree compiles clean under Java 21 -- `-Werror` is on, so that is a real
result and not a suppressed one -- which means a machine with only a JDK 21
toolchain can build the distribution by overriding the compiler level:

```bash
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    ./mvnw clean package -P cubrid -DskipTests \
    -Dmaven.compiler.source=21 -Dmaven.compiler.target=21
```

Keep the override on the command line. `pom.xml` stays at 23 so the fork does
not diverge from upstream over one machine's toolchain, and the jar this
produces targets 21, so it needs a JRE of at least that to run.

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

YCSB, full cycle. `scalefactor` here is thousands of rows in `USERTABLE`, so
the shipped value of 10 loads 10,000:

```bash
java -jar benchbase.jar -b ycsb \
    -c config/cubrid/sample_ycsb_config.xml \
    --create=true --load=true --execute=true
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

Every config XML has the same shape, and the elements below are the whole set
BenchBase reads. Defaults are the framework's, not this fork's; where the
shipped CUBRID samples differ, that is called out.

### Connection

| Element | Shipped value | Notes |
|---|---|---|
| `type` | `CUBRID` | Selects `ddl-cubrid.sql` / `dialect-cubrid.xml` by name, and the identifier-escaping and column-name rules in `DatabaseType` |
| `driver` | `cubrid.jdbc.driver.CUBRIDDriver` | |
| `url` | `jdbc:cubrid:<host>:<port>:<db>:::` | TPC-C and YCSB samples use port 33000, sysbench 35000 |
| `username` / `password` | `dba` / empty | CUBRID's default DBA account |
| `isolation` | `TRANSACTION_READ_COMMITTED` | Framework default is the driver's. See [Isolation](#isolation) |
| `reconnectOnConnectionFailure` | `true` | Framework default `false` |
| `newConnectionPerTxn` | unset (`false`) | Turning it on measures connection setup as much as the workload |

### Load and workload

| Element | Default | Effect |
|---|---|---|
| `scalefactor` | `1.0` | Benchmark-specific; see below |
| `terminals` | required | Client threads during `--execute` |
| `batchsize` | `128` | Rows per JDBC batch during `--load` |
| `loaderThreads` | CPU count | A **ceiling**, not a count; see below |
| `works/work/time` | `0` | Seconds per phase. `0` is untimed and valid only with `serial` |
| `works/work/warmup` | `0` | Seconds discarded before measurement begins |
| `works/work/rate` | required | Target requests/second, or `unlimited` |
| `works/work/weights` | required | Transaction mix, in the order `transactiontypes` declares them |
| `works/work/@arrival` | `regular` | `poisson` for an open-loop arrival process |
| `works/work/active_terminals` | `terminals` | Lets one phase use fewer terminals than are allocated |
| `works/work/serial` | `false` | Each transaction type once, in order; forces one terminal |
| `ddlpath` | unset | Filesystem DDL, overriding the classpath lookup. The startup banner prints `DDL Path: null` when unset, which is normal |
| `sessionsetupfile` | unset | SQL run on every new connection |
| `afterload` | unset | SQL run once after `--load` |
| `selectivity` | unset | Only consulted by benchmarks that declare it |

### What `scalefactor` means, per benchmark

| Benchmark | `scalefactor` is | Shipped |
|---|---|---|
| TPC-C | Warehouses | `1` |
| TPC-H | The TPC-H scale factor handed to the dbgen generators | no config yet |
| YCSB | Thousands of rows in `USERTABLE` (`RECORD_COUNT = 1000`) | `10` → 10,000 rows |

YCSB reads two parameters of its own, neither of which the shipped config sets:
`fieldSize` (characters per field; default and hard maximum 100) and
`skewFactor` (the Zipfian constant; default 0.99, rejected unless strictly
between 0 and 1).

### `loaderThreads` is a ceiling, not a thread count

This is the parameter most likely to mislead. `loaderThreads` becomes
`maxConcurrent` in `ThreadUtil.runLoaderThreads()`; how many loader threads
exist at all is decided by each benchmark's `createLoaderThreads()`. Raising it
cannot create parallelism the benchmark never produced.

The three benchmarks partition differently:

- **TPC-C** creates one loader thread per warehouse, so `scalefactor` governs
  load parallelism as well as data size.
- **TPC-H** creates one per table, so its load parallelism is fixed and
  independent of `scalefactor`.
- **YCSB** splits the row range into chunks of `THREAD_BATCH_SIZE = 50000`:

  | `scalefactor` | Rows | Loader threads |
  |---:|---:|---:|
  | 10 | 10,000 | 1 |
  | 50 | 50,000 | 1 |
  | 100 | 100,000 | 2 |
  | 1000 | 1,000,000 | 20 |

At YCSB's shipped `scalefactor` of 10 the load is single-threaded whatever
`loaderThreads` says: the banner reports `Loader Threads: 16` and the pool is
still built with a size of 1. Parallelise a YCSB load by raising `scalefactor`
past 50, not by raising `loaderThreads`.

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

- `DROP TABLE ... CASCADE CONSTRAINTS`, Oracle-style. This is a convenience, not
  a requirement: the generic TPC-C file drops child tables before parents, and
  that ordering alone gets it through CUBRID twice in a row. `CASCADE
  CONSTRAINTS` buys independence from the ordering. What CUBRID does reject is a
  bare `CASCADE`, which is why CH-benCHmark needs its own file.
- `new_order` declares its primary key before its foreign key, so CUBRID does
  not reject the second index when the FK and PK cover identical columns.

**TPC-H ships one.** `benchmarks/tpch/dialect-cubrid.xml` overrides 11 of the 22
queries (Q1, Q3, Q4, Q5, Q6, Q10, Q11, Q12, Q14, Q15, Q20), chiefly because the
generic stream does date arithmetic with an `INTERVAL` literal, which CUBRID's
parser rejects. The two forms, run against CUBRID 11.5:

```sql
-- generic
... WHERE l_shipdate <= DATE '1998-12-01' - INTERVAL 90 DAY
    ERROR: Syntax error: unexpected 'INTERVAL'

-- dialect-cubrid.xml
... WHERE l_shipdate <= DATE_SUB(DATE '1998-12-01', INTERVAL 90 DAY)
    1 row selected.
```

So the generic stream fails at Q1 and never reaches Q2. The XSD constraint above
stops mattering the moment even one query needs an override, which is exactly
the condition for adding the file.

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

Seven upstream source files are modified, `README.md` gains two additive blocks,
and everything else is a new file. No other path is touched.

```
src/main/java/com/oltpbenchmark/types/DatabaseType.java      (one enum row added)
src/main/java/com/oltpbenchmark/util/SQLUtil.java            (getSchema() fallback + Number conversion -- see below)
src/main/java/com/oltpbenchmark/LatencyRecord.java           (latency widened to int64 -- see below)
src/main/java/com/oltpbenchmark/ThreadBench.java             (same)
src/main/java/com/oltpbenchmark/DistributionStatistics.java  (same)
src/main/java/com/oltpbenchmark/util/ResultWriter.java       (same)
pom.xml                                                      (one <profile id="cubrid"> block)
README.md                                                    (fork banner + CUBRID Support section)
CUBRID.md                                                    (this file)
src/test/java/com/oltpbenchmark/TestDistributionStatistics.java (new -- pins the latency width)
src/main/resources/benchmarks/tpcc/ddl-cubrid.sql            (new)
src/main/resources/benchmarks/tpch/ddl-cubrid.sql            (new)
src/main/resources/benchmarks/tpch/dialect-cubrid.xml        (new)
src/main/resources/benchmarks/chbenchmark/ddl-cubrid.sql     (new)
src/main/resources/benchmarks/auctionmark/ddl-cubrid.sql     (new)
src/main/resources/benchmarks/otmetrics/ddl-cubrid.sql       (new)
src/main/resources/benchmarks/sibench/ddl-cubrid.sql         (new)
src/main/resources/benchmarks/sibench/dialect-cubrid.xml     (new)
src/main/resources/benchmarks/twitter/ddl-cubrid.sql         (new)
src/main/resources/benchmarks/wikipedia/ddl-cubrid.sql       (new)
config/cubrid/                                               (new directory)
config/postgres/harness_tpcc_config.xml                      (new -- cross-engine comparison)
config/mysql/harness_tpcc_config.xml                         (new -- cross-engine comparison)
scripts/install-cubrid-jdbc.sh                               (new)
scripts/tpcc-consistency-conditions.sql                      (new)
scripts/tpcc-consistency-conditions-pg.sql                   (new)
scripts/tpcc-consistency-conditions-mysql.sql                (new)
data/templated/                                              (untouched -- see above)
```

The four latency files widen transaction latency from int32 to int64
microseconds. Like the `getSchema()` fallback the change names no engine, so it
belongs upstream rather than here; it is listed as upstream-pending on the same
terms.

It took two commits, because the first fix was half of one. `729002d` widened
the recording path, and an 86-minute CUBRID TPC-H Q20 run then wrote a correct
2594811975 us into its raw CSV while the `summary.json` beside it reported every
percentile as exactly `2147483647`. `DistributionStatistics` keeps percentiles
in a `long` but hands them out through `double` getters, and `toMap()` cast
those doubles to `int` — and a double-to-int cast **saturates** where a
long-to-int cast **wraps**. So the recording path failed loudly and the summary
path failed silently, reporting a plausible 35.8-minute answer. `c2f75a3` widens
`toMap()` and adds a test that pins the three behaviours apart, since which cast
is used decides whether a too-large latency is wrong-and-visible or
wrong-and-silent.

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

The same file carries a second engine-agnostic fix. `getLong ()`,
`getInteger ()` and `getDouble ()` each accepted a fixed handful of boxed types
and returned null for anything else, logging `BAD BAD BAD`. CUBRID's driver
returns `Short` for a `tinyint` column, which is a perfectly ordinary thing for
a driver to do, and SEATS died on it:

    java.lang.NullPointerException: Cannot invoke "java.lang.Long.longValue()"
      because the return value of "SQLUtil.getLong(Object)" is null
        at SEATSProfile.loadConfigHistograms (SEATSProfile.java:334)

Each converter now falls back to `Number`, which subsumes the types they already
listed and every other boxed numeric a driver might hand back. AuctionMark's
`LoadConfig` was failing on the same gap and recovered with it.

**Upstream status: not yet filed.** Both changes name no engine. File them
against `cmu-db/benchbase` and replace this note with the outcome.
