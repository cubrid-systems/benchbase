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
| `isolation`   | `TRANSACTION_REPEATABLE_READ`        | See isolation note below               |

## Isolation Note

REPEATABLE_READ is the working default pending M0.5 probe finalization — see
ADR-3 in the plan (`/data/cub_sys/.omc/plans/cubrid-benchmarking-phase1.md`).
The M0.5 empirical probe will measure tpmC and abort rate across READ_COMMITTED,
REPEATABLE_READ, and SERIALIZABLE, and select the primary level from data.
Update `<isolation>` in the config XML once M0.5 closes.

## Fork Allowlist (Rebase Hygiene)

All CUBRID-specific changes in this fork are confined to the following paths.
No other files are modified. See M7 in the plan for the formal allowlist check.

```
src/main/java/com/oltpbenchmark/types/DatabaseType.java  (one enum row added)
pom.xml                                                  (one <profile id="cubrid"> block)
src/main/resources/benchmarks/tpcc/dialect-cubrid.xml   (new)
src/main/resources/benchmarks/tpcc/ddl-cubrid.sql       (new)
config/cubrid/                                           (new directory)
scripts/install-cubrid-jdbc.sh                          (new)
CUBRID.md                                               (this file)
```

When rebasing against upstream BenchBase:
1. The `DatabaseType.java` enum row is a pure addition — no conflict expected
   unless upstream adds entries in the same alphabetical region.
2. The `pom.xml` profile block is a pure addition between `postgres` and `mysql`
   profiles — no conflict expected unless upstream restructures profiles.
3. All other paths are new files — no conflict expected.
