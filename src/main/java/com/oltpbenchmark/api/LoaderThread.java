/*
 * Copyright 2020 by OLTPBenchmark Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

package com.oltpbenchmark.api;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * A LoaderThread is responsible for loading some portion of a benchmark's database. Note that each
 * LoaderThread has its own database Connection handle.
 */
public abstract class LoaderThread implements Runnable {

  private static final Logger LOG = LoggerFactory.getLogger(LoaderThread.class);

  private final BenchmarkModule benchmarkModule;

  public LoaderThread(BenchmarkModule benchmarkModule) {
    this.benchmarkModule = benchmarkModule;
  }

  @Override
  public final void run() {
    beforeLoad();
    try (Connection conn = benchmarkModule.makeConnection()) {
      // Under autocommit, how a batch commits is the driver's choice: once with a driver that
      // rewrites it into one INSERT (pgjdbc reWriteBatchedInserts, Connector/J
      // rewriteBatchedStatements), once a row with CUBRID's. Commit each batch ourselves.
      conn.setAutoCommit(false);
      load(commitEachStatement(conn));
      conn.commit();
    } catch (SQLException ex) {
      SQLException next_ex = ex.getNextException();
      String msg =
          String.format(
              "Unexpected error when loading %s database",
              benchmarkModule.getBenchmarkName().toUpperCase());
      LOG.error(msg, next_ex);
      throw new RuntimeException(ex);
    } finally {
      afterLoad();
    }
  }

  /**
   * conn, whose statements commit after each update and each batch and roll back after a failure,
   * as under autocommit, except that a batch commits once.
   */
  private static Connection commitEachStatement(Connection conn) {
    return (Connection)
        Proxy.newProxyInstance(
            LoaderThread.class.getClassLoader(),
            new Class<?>[] {Connection.class},
            (proxy, method, args) -> {
              Object result = invoke(conn, method, args);
              if (result instanceof Statement stmt) {
                return commitAfterUpdates(conn, stmt, method.getReturnType());
              }
              return result;
            });
  }

  private static Object commitAfterUpdates(Connection conn, Statement stmt, Class<?> type) {
    return Proxy.newProxyInstance(
        LoaderThread.class.getClassLoader(),
        new Class<?>[] {type},
        (proxy, method, args) -> {
          Object result;
          try {
            result = invoke(stmt, method, args);
          } catch (SQLException ex) {
            // PostgreSQL rejects every later statement in a failed transaction, and the loaders
            // log an error and go on with the connection. Only the failed statement is undone.
            try {
              conn.rollback();
            } catch (SQLException rollbackEx) {
              ex.addSuppressed(rollbackEx);
            }
            throw ex;
          }
          String name = method.getName();
          // execute() is false for an update; a query's results stay open until the next commit.
          if (name.equals("executeBatch")
              || name.equals("executeLargeBatch")
              || name.equals("executeUpdate")
              || name.equals("executeLargeUpdate")
              || (name.equals("execute") && Boolean.FALSE.equals(result))) {
            conn.commit();
          }
          return result;
        });
  }

  private static Object invoke(Object target, Method method, Object[] args) throws Throwable {
    try {
      return method.invoke(target, args);
    } catch (InvocationTargetException ex) {
      throw ex.getCause();
    }
  }

  /**
   * This is the method that each LoaderThread has to implement
   *
   * @param conn
   * @throws SQLException
   */
  public abstract void load(Connection conn) throws SQLException;

  public void beforeLoad() {
    // useful for implementing waits for countdown latches, this ensures we open the connection
    // right before its used to avoid stale connections
  }

  public void afterLoad() {
    // useful for counting down latches
  }
}
