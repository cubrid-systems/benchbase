-- ddl-cubrid.sql
-- Twitter schema for CUBRID 11.x.
--
-- One change from ddl-generic.sql: added_tweets.id is AUTO_INCREMENT.
--
-- InsertTweet writes `INSERT INTO added_tweets (uid,text,createdate)` and never
-- supplies id, so the column has to generate its own. The generic file declares
-- it a plain `bigint NOT NULL`, which is why every InsertTweet fails there with
--   Missing value for attribute "id" with the NOT NULL constraint.
-- ddl-mysql.sql spells this AUTO_INCREMENT and ddl-postgres.sql spells it
-- serial; CUBRID accepts the MySQL form.
--
-- tweets.id is left alone: it is loaded with explicit values and never
-- generated. Everything else in the file is accepted unchanged.

-- MySQL ddl from Twitter dump

DROP TABLE IF EXISTS added_tweets;
DROP TABLE IF EXISTS tweets;
DROP TABLE IF EXISTS followers;
DROP TABLE IF EXISTS follows;
DROP TABLE IF EXISTS user_profiles;

CREATE TABLE user_profiles
(
    uid          int NOT NULL,
    name         varchar(255) DEFAULT NULL,
    email        varchar(255) DEFAULT NULL,
    partitionid  int          DEFAULT NULL,
    partitionid2 tinyint      DEFAULT NULL,
    followers    int          DEFAULT NULL,
    PRIMARY KEY (uid)
);
CREATE INDEX IDX_USER_FOLLOWERS ON user_profiles (followers);
CREATE INDEX IDX_USER_PARTITION ON user_profiles (partitionid);

CREATE TABLE followers
(
    f1 int NOT NULL REFERENCES user_profiles (uid),
    f2 int NOT NULL REFERENCES user_profiles (uid),
    PRIMARY KEY (f1, f2)
);

CREATE TABLE follows
(
    f1 int NOT NULL REFERENCES user_profiles (uid),
    f2 int NOT NULL REFERENCES user_profiles (uid),
    PRIMARY KEY (f1, f2)
);

-- TODO: id AUTO_INCREMENT
CREATE TABLE tweets
(
    id         bigint    NOT NULL,
    uid        int       NOT NULL REFERENCES user_profiles (uid),
    text       char(140) NOT NULL,
    createdate datetime DEFAULT NULL,
    PRIMARY KEY (id)
);
CREATE INDEX IDX_TWEETS_UID ON tweets (uid);

-- TODO: id auto_increment
CREATE TABLE added_tweets
(
    id         bigint    NOT NULL AUTO_INCREMENT,
    uid        int       NOT NULL REFERENCES user_profiles (uid),
    text       char(140) NOT NULL,
    createdate datetime DEFAULT NULL,
    PRIMARY KEY (id)
);
CREATE INDEX IDX_ADDED_TWEETS_UID ON added_tweets (uid);
