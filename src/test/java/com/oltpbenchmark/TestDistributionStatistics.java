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

package com.oltpbenchmark;

import static org.junit.Assert.assertEquals;

import java.util.Map;
import org.junit.Test;

/**
 * A transaction slower than 35.8 minutes does not fit in an int of microseconds. That is
 * unreachable for OLTP and ordinary for a TPC-H query against a slow engine, so the whole latency
 * path has to be long-clean end to end -- not just where the value is recorded, but everywhere it
 * is handed on.
 */
public class TestDistributionStatistics {

  /** 2594811975 us == 43.2 minutes: a real CUBRID TPC-H Q20 at SF=0.1. */
  private static final long Q20 = 2594811975L;

  @Test
  public void testPercentilesSurviveBeyondIntRange() {
    DistributionStatistics stats = DistributionStatistics.computeStatistics(new long[] {Q20});
    Map<String, Long> map = stats.toMap();

    // An int cast would have saturated all of these to Integer.MAX_VALUE, which reads as an
    // ordinary 35.8-minute answer and gives no sign that anything was lost.
    for (Map.Entry<String, Long> e : map.entrySet()) {
      assertEquals(e.getKey(), Q20, (long) e.getValue());
    }
  }

  /**
   * The distribution is computed from the same longs the raw CSV is written from, so the summary
   * and the raw rows must not be able to disagree.
   */
  @Test
  public void testSummaryAgreesWithRawValues() {
    long[] values = {1_000L, Q20, Integer.MAX_VALUE + 1L};
    DistributionStatistics stats = DistributionStatistics.computeStatistics(values.clone());
    Map<String, Long> map = stats.toMap();

    assertEquals(1_000L, (long) map.get("Minimum Latency (microseconds)"));
    assertEquals(Q20, (long) map.get("Maximum Latency (microseconds)"));
    // sum/3, floored by the cast -- still far above what an int could hold.
    assertEquals(
        (1_000L + Q20 + Integer.MAX_VALUE + 1L) / 3,
        (long) map.get("Average Latency (microseconds)"));
  }
}
