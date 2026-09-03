-- ddl-cubrid.sql
-- CH-benCHmark's three extra tables (region, nation, supplier) for CUBRID 11.x.
--
-- Derived from ddl-generic.sql. One difference, in the DROP statements only:
-- CUBRID spells the clause CASCADE CONSTRAINTS, not a bare CASCADE, so the
-- generic file fails at its very first statement with
--   ERROR: In line 1, column 36 before END OF STATEMENT
-- Everything below the DROPs is accepted unchanged: inline REFERENCES with
-- ON DELETE CASCADE, char(n), numeric(p,s), and a trailing PRIMARY KEY are all
-- fine, because each foreign key here points at a table created earlier in the
-- file whose primary key therefore already exists.
--
-- CH-benCHmark also needs the TPC-C tables; run it as `-b tpcc,chbenchmark`.

DROP TABLE IF EXISTS region CASCADE CONSTRAINTS;
DROP TABLE IF EXISTS nation CASCADE CONSTRAINTS;
DROP TABLE IF EXISTS supplier CASCADE CONSTRAINTS;

create table region
(
    r_regionkey int       not null,
    r_name      char(55)  not null,
    r_comment   char(152) not null,
    PRIMARY KEY (r_regionkey)
);

create table nation
(
    n_nationkey int    not null,
   n_name char(25) not null,
   n_regionkey int not null references region(r_regionkey) ON DELETE CASCADE,
   n_comment char(152) not null,
   PRIMARY KEY ( n_nationkey )
);

create table supplier (
   su_suppkey int not null,
   su_name char(25) not null,
   su_address varchar(40) not null,
   su_nationkey int not null references nation(n_nationkey)  ON DELETE CASCADE,
   su_phone char(15) not null,
   su_acctbal numeric(12,2) not null,
   su_comment char(101) not null,
   PRIMARY KEY ( su_suppkey )
);