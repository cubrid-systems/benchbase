# BenchBase

[![BenchBase (Java with Maven)](https://github.com/cmu-db/benchbase/actions/workflows/maven.yml/badge.svg?branch=main)](https://github.com/cmu-db/benchbase/actions/workflows/maven.yml)

BenchBase (formerly [OLTPBench](https://github.com/oltpbenchmark/oltpbench/)) is a Multi-DBMS SQL Benchmarking Framework via JDBC.

> **This is CUBRID's fork of [`cmu-db/benchbase`](https://github.com/cmu-db/benchbase).**
> It adds CUBRID 11.x as a benchmark target and changes nothing else, so everything
> upstream documents below still applies as written. For the CUBRID build, configs,
> and caveats, jump to [CUBRID Support](#cubrid-support) or read
> [CUBRID.md](./CUBRID.md). The badge above tracks upstream CI, not this fork.

**Table of Contents**

- [Quickstart](#quickstart)
- [CUBRID Support](#cubrid-support)
- [Description](#description)
- [Usage Guide](#usage-guide)
- [Contributing](#contributing)
- [Known Issues](#known-issues)
- [Credits](#credits)
- [Citing This Repository](#citing-this-repository)

---

## Quickstart

To clone and build BenchBase using the `postgres` profile,

```bash
git clone --depth 1 https://github.com/cmu-db/benchbase.git
cd benchbase
./mvnw clean package -P postgres
```

This produces artifacts in the `target` folder, which can be extracted,

```bash
cd target
tar xvzf benchbase-postgres.tgz
cd benchbase-postgres
```

Inside this folder, you can run BenchBase. For example, to execute the `tpcc` benchmark,

```bash
java -jar benchbase.jar -b tpcc -c config/postgres/sample_tpcc_config.xml --create=true --load=true --execute=true
```

A full list of options can be displayed,

```bash
java -jar benchbase.jar -h
```

---

## CUBRID Support

This fork adds [CUBRID](https://www.cubrid.org/) 11.x as a BenchBase target. The
integration is deliberately thin — one `DatabaseType` enum entry, one Maven
profile, one engine-agnostic driver-compatibility fix in `SQLUtil`, and otherwise
only new resource and config files. [CUBRID.md](./CUBRID.md) carries the full
rationale, the rebase allowlist, and the reasoning behind the defaults.

| Benchmark | Status |
|-----------|--------|
| TPC-C | Ready — `config/cubrid/sample_tpcc_config.xml` |
| TPC-H | Ready — `config/cubrid/sample_tpch_config.xml`, all 22 queries verified end to end |
| YCSB | Ready — `config/cubrid/sample_ycsb_config.xml`, no CUBRID DDL or dialect needed |
| CH-benCHmark, AuctionMark | Schema ready (`ddl-cubrid.sql`); no config yet |
| sysbench OLTP clone | Config committed, never run |

Thirteen more benchmarks take upstream's generic schema on CUBRID unchanged and
need only a config — `tatp`, `smallbank` and `voter` have been run end to end to
confirm that holds past the schema. Five need their own DDL. Which, and why, is
in [What the rest of the suite would need](./CUBRID.md#what-the-rest-of-the-suite-would-need).

### Prerequisites

- A running **CUBRID 11.x** server with the target database created and its
  broker reachable at the host and port in your config XML.
- **Java 23** and **Maven** (or the bundled `./mvnw`). JDK 21 also builds this
  tree — see [Building on a JDK older than 23](./CUBRID.md#building-on-a-jdk-older-than-23).
- The **CUBRID JDBC jar** in your local Maven repository. CUBRID does not publish
  to Maven Central, so the `cubrid:cubrid-jdbc` coordinate used by the `cubrid`
  profile has to be satisfied locally:

  ```bash
  ./scripts/install-cubrid-jdbc.sh                  # auto-detects $CUBRID/jdbc/cubrid-jdbc-*.jar
  ./scripts/install-cubrid-jdbc.sh /path/to/cubrid-jdbc-11.3.2.0058.jar
  ```

### Build and run

```bash
git clone https://github.com/cubrid-systems/benchbase.git
cd benchbase
./scripts/install-cubrid-jdbc.sh
./mvnw clean package -P cubrid -DskipTests

tar xvzf target/benchbase-cubrid.tgz -C target/
cd target/benchbase-cubrid
```

TPC-C, full cycle:

```bash
java -jar benchbase.jar -b tpcc -c config/cubrid/sample_tpcc_config.xml \
    --create=true --load=true --execute=true
```

TPC-H. `serial` in the shipped config runs each of the 22 queries exactly once,
in order, which is the shape you want when checking a dialect covers the stream:

```bash
java -jar benchbase.jar -b tpch -c config/cubrid/sample_tpch_config.xml \
    --create=true --load=true --execute=true
```

YCSB, full cycle. Its `scalefactor` is thousands of rows in `USERTABLE`, so the
shipped `10` loads 10,000:

```bash
java -jar benchbase.jar -b ycsb -c config/cubrid/sample_ycsb_config.xml \
    --create=true --load=true --execute=true
```

The sysbench clone runs through upstream's `templated` plugin, which has no
loader — `sbtest1` must already exist and be populated. Its DDL and expected row
range are in a comment at the top of the config:

```bash
java -jar benchbase.jar -b templated \
    -c config/cubrid/sysbench_templated_config.xml --execute=true
```

Which config elements exist, what each does, and what `scalefactor` means for
each benchmark are documented in
[Configuration](./CUBRID.md#configuration). Read
[`loaderThreads` is a ceiling, not a thread count](./CUBRID.md#loaderthreads-is-a-ceiling-not-a-thread-count)
before tuning a load — it is the parameter most likely to mislead.

### Verifying a load

After `--load=true`, check the four TPC-C §3.3.2 consistency conditions with the
shipped SQL. Every query must report `violations: 0`:

```bash
csql -C -u dba demodb@localhost -i scripts/tpcc-consistency-conditions.sql
```

Equivalents for cross-engine comparison runs ship alongside it —
`scripts/tpcc-consistency-conditions-pg.sql` and
`scripts/tpcc-consistency-conditions-mysql.sql`, paired with
`config/postgres/harness_tpcc_config.xml` and
`config/mysql/harness_tpcc_config.xml`.

### Caveats

- `TRANSACTION_READ_COMMITTED` is the shipped default, chosen from a single
  integration observation rather than a probe. See
  [Isolation](./CUBRID.md#isolation).
- TPC-C ships no `dialect-cubrid.xml` on purpose; TPC-H needs one. The XSD reason
  is in [Dialect files](./CUBRID.md#dialect-files).

---

## Description

Benchmarking is incredibly useful, yet endlessly painful. This benchmark suite is the result of a group of
PhDs/post-docs/professors getting together and combining their workloads/frameworks/experiences/efforts. We hope this
will save other people's time, and will provide an extensible platform, that can be grown in an open-source fashion.

BenchBase is a multi-threaded load generator. The framework is designed to be able to produce variable rate,
variable mixture load against any JDBC-enabled relational database. The framework also provides data collection
features, e.g., per-transaction-type latency and throughput logs.

The BenchBase framework has the following benchmarks:

* [AuctionMark](https://github.com/cmu-db/benchbase/wiki/AuctionMark)
* [CH-benCHmark](https://github.com/cmu-db/benchbase/wiki/CH-benCHmark)
* [Epinions.com](https://github.com/cmu-db/benchbase/wiki/epinions)
* hyadapt -- pending configuration files
* [NoOp](https://github.com/cmu-db/benchbase/wiki/NoOp)
* [OT-Metrics](https://github.com/cmu-db/benchbase/wiki/OT-Metrics)
* [Resource Stresser](https://github.com/cmu-db/benchbase/wiki/Resource-Stresser)
* [SEATS](https://github.com/cmu-db/benchbase/wiki/Seats)
* [SIBench](https://github.com/cmu-db/benchbase/wiki/SIBench)
* [SmallBank](https://github.com/cmu-db/benchbase/wiki/SmallBank)
* [TATP](https://github.com/cmu-db/benchbase/wiki/TATP)
* [TPC-C](https://github.com/cmu-db/benchbase/wiki/TPC-C)
* [TPC-H](https://github.com/cmu-db/benchbase/wiki/TPC-H)
* TPC-DS -- pending configuration files
* [Twitter](https://github.com/cmu-db/benchbase/wiki/Twitter)
* [Voter](https://github.com/cmu-db/benchbase/wiki/Voter)
* [Wikipedia](https://github.com/cmu-db/benchbase/wiki/Wikipedia)
* [YCSB](https://github.com/cmu-db/benchbase/wiki/YCSB)

This framework is design to allow for easy extension. We provide stub code that a contributor can use to include a new
benchmark, leveraging all the system features (logging, controlled speed, controlled mixture, etc.)

---

## Usage Guide

### How to Build
Run the following command to build the distribution for a given database specified as the profile name (`-P`).  The following profiles are currently supported: `postgres`, `mysql`, `mariadb`, `sqlite`, `cockroachdb`, `phoenix`, `spanner`, and `cubrid` (see [CUBRID Support](#cubrid-support) for its extra prerequisite).

```bash
./mvnw clean package -P <profile name>
```

The following files will be placed in the `./target` folder:

* `benchbase-<profile name>.tgz`
* `benchbase-<profile name>.zip`

### How to Run
Once you build and unpack the distribution, you can run `benchbase` just like any other executable jar.  The following examples assume you are running from the root of the expanded `.zip` or `.tgz` distribution.  If you attempt to run `benchbase` outside of the distribution structure you may encounter a variety of errors including `java.lang.NoClassDefFoundError`.

To bring up help contents:
```bash
java -jar benchbase.jar -h
```

To execute the `tpcc` benchmark:
```bash
java -jar benchbase.jar -b tpcc -c config/postgres/sample_tpcc_config.xml --create=true --load=true --execute=true
```

For composite benchmarks like `chbenchmark`, which require multiple schemas to be created and loaded, you can provide a comma separated list:
```bash
java -jar benchbase.jar -b tpcc,chbenchmark -c config/postgres/sample_chbenchmark_config.xml --create=true --load=true --execute=true
```

The following options are provided:

```text
usage: benchbase
 -b,--bench <arg>               [required] Benchmark class. Currently
                                supported: [tpcc, tpch, tatp, wikipedia,
                                resourcestresser, twitter, epinions, ycsb,
                                seats, auctionmark, chbenchmark, voter,
                                sibench, noop, smallbank, hyadapt,
                                otmetrics, templated]
 -c,--config <arg>              [required] Workload configuration file
    --clear <arg>               Clear all records in the database for this
                                benchmark
    --create <arg>              Initialize the database for this benchmark
 -d,--directory <arg>           Base directory for the result files,
                                default is current directory
    --dialects-export <arg>     Export benchmark SQL to a dialects file
    --execute <arg>             Execute the benchmark workload
 -h,--help                      Print this help
 -im,--interval-monitor <arg>   Throughput Monitoring Interval in
                                milliseconds
 -jh,--json-histograms <arg>    Export histograms to JSON file
    --load <arg>                Load data using the benchmark's data
                                loader
 -s,--sample <arg>              Sampling window
```

### How to Run with Maven

Instead of first building, packaging and extracting before running benchbase, it is possible to execute benchmarks directly against the source code using Maven. Once you have the project cloned you can run any benchmark from the root project directory using the Maven `exec:java` goal. For example, the following command executes the `tpcc` benchmark against `postgres`:

```
mvn clean compile exec:java -P postgres -Dexec.args="-b tpcc -c config/postgres/sample_tpcc_config.xml --create=true --load=true --execute=true"
```

this is equivalent to the steps above but eliminates the need to first package and then extract the distribution.

### How to Enable Logging

To enable logging, e.g., for the PostgreSQL JDBC driver, add the following JVM property when starting...

```
-Djava.util.logging.config.file=src/main/resources/logging.properties
```

To modify the logging level you can update [`logging.properties`](src/main/resources/logging.properties) and/or [`log4j.properties`](src/main/resources/log4j.properties).

### How to Release

```
./mvnw -B release:prepare
./mvnw -B release:perform
```

### How use with Docker

- Build or pull a dev image to help building from source:

  ```sh
  ./docker/benchbase/build-dev-image.sh
  ./docker/benchbase/run-dev-image.sh
  ```

  or

  ```sh
  docker run -it --rm --pull \
    -v /path/to/benchbase-source:/benchbase \
    -v $HOME/.m2:/home/containeruser/.m2 \
    benchbase.azure.cr.io/benchbase-dev
  ```

- Build the full image:

  ```sh
  # build an image with all profiles
  ./docker/benchbase/build-full-image.sh

  # or if you only want to build some of them
  BENCHBASE_PROFILES='postgres mysql' ./docker/benchbase/build-full-image.sh
  ```

- Run the image for a given profile:

  ```sh
  BENCHBASE_PROFILE='postgres' ./docker/benchbase/run-full-image.sh --help # or other benchbase args as before
  ```

  or

  ```sh
  docker run -it --rm --env BENCHBASE_PROFILE='postgres' \
    -v results:/benchbase/results benchbase.azurecr.io/benchbase --help # or other benchbase args as before
  ```

> See the [docker/benchbase/README.md](./docker/benchbase/) for further details.

[Github Codespaces](https://github.com/features/codespaces) and [VSCode devcontainer](https://code.visualstudio.com/docs/remote/containers) support is also available.

### How to Add Support for a New Database

Please see the existing MySQL and PostgreSQL code for an example.

---

## Contributing

We welcome all contributions! Please open a [pull request](https://github.com/cmu-db/benchbase/pulls). Common contributions may include:

- Adding support for a new DBMS.
- Adding more tests of existing benchmarks.
- Fixing any bugs or known issues.

Please see the [CONTRIBUTING.md](./CONTRIBUTING.md) for addition notes.

## Known Issues

Please use [GitHub's issue tracker](https://github.com/cmu-db/benchbase/issues) for all issues.

## Credits

BenchBase is the official modernized version of the original OLTPBench.

The original OLTPBench code was largely written by the authors of the original paper, [OLTP-Bench: An Extensible Testbed for Benchmarking Relational Databases](http://www.vldb.org/pvldb/vol7/p277-difallah.pdf), D. E. Difallah, A. Pavlo, C. Curino, and P. Cudré-Mauroux. In VLDB 2014. Please see the citation guide below.

A significant portion of the modernization was contributed by [Tim Veil @ Cockroach Labs](https://github.com/timveil-cockroach), including but not limited to:

* Built with and for Java ~~17~~ 21.
* Migration from Ant to Maven.
  * Reorganized project to fit Maven structure.
  * Removed static `lib` directory and dependencies.
  * Updated required dependencies and removed unused or unwanted dependencies.
  * Moved all non `.java` files to standard Maven `resources` directory.
  * Shipped with [Maven Wrapper](https://maven.apache.org/wrapper).
* Improved packaging and versioning.
    * Moved to Calendar Versioning (https://calver.org/).
    * Project is now distributed as a `.tgz` or `.zip` with an executable `.jar`.
    * All code updated to read `resources` from inside `.jar` instead of directory.
* Moved from direct dependence on Log4J to SLF4J.
* Reorganized and renamed many files for clarity and consistency.
* Applied countless fixes based on "Static Analysis".
    * JDK migrations (boxing, un-boxing, etc.).
    * Implemented `try-with-resources` for all `java.lang.AutoCloseable` instances.
    * Removed calls to `printStackTrace()` or `System.out.println` in favor of proper logging.
* Reformatted code and cleaned up imports.
* Removed all calls to `assert`.
* Removed various forms of dead code and stale configurations.
* Removed calls to `commit()` during `Loader` operations.
* Refactored `Worker` and `Loader` usage of `Connection` objects and cleaned up transaction handling.
* Introduced [Dependabot](https://dependabot.com/) to keep Maven dependencies up to date.
* Simplified output flags by removing most of them, generally leaving the reporting functionality enabled by default.
* Provided an alternate `Catalog` that can be populated directly from the configured Benchmark database. The old catalog was proxied through `HSQLDB` -- this remains an option for DBMSes that may have incomplete catalog support.

## Citing This Repository

If you use this repository in an academic paper, please cite this repository:

> D. E. Difallah, A. Pavlo, C. Curino, and P. Cudré-Mauroux, "OLTP-Bench: An Extensible Testbed for Benchmarking Relational Databases," PVLDB, vol. 7, iss. 4, pp. 277-288, 2013.

The BibTeX is provided below for convenience.

```bibtex
@article{DifallahPCC13,
  author = {Djellel Eddine Difallah and Andrew Pavlo and Carlo Curino and Philippe Cudr{\'e}-Mauroux},
  title = {OLTP-Bench: An Extensible Testbed for Benchmarking Relational Databases},
  journal = {PVLDB},
  volume = {7},
  number = {4},
  year = {2013},
  pages = {277--288},
  url = {http://www.vldb.org/pvldb/vol7/p277-difallah.pdf},
}
```
