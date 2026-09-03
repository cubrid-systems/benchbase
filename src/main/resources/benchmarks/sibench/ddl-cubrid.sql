-- ddl-cubrid.sql
-- SIBench schema for CUBRID 11.x.
--
-- One change from ddl-generic.sql: the column is quoted. `value` is a CUBRID
-- reserved word and is rejected in DDL and in queries alike, so quoting it here
-- is only half the fix -- both of this benchmark's procedures name the column in
-- SQL, which is why dialect-cubrid.xml exists beside this file. See the comment
-- there.

DROP TABLE IF EXISTS SITEST CASCADE CONSTRAINTS;
CREATE TABLE SITEST (
    id      INT PRIMARY KEY,
    [value] INT NOT NULL
);
