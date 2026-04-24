-- TPC-C consistency conditions 1-4 (TPC-C v5.11 §3.3.2) — PostgreSQL port.
-- Reference: BenchBase loaded `tpcc` at SF=1 on PostgreSQL.
-- A passing run reports `0` (or empty) for every violation query below.
-- Schema note: BenchBase on Postgres uses table `oorder` (same as CUBRID).

-- Condition 1: W_YTD = sum(D_YTD) for each warehouse.
SELECT 'COND1 violations: ' || COUNT(*)
FROM (
    SELECT w.w_id,
           w.w_ytd,
           (SELECT SUM(d.d_ytd) FROM district d WHERE d.d_w_id = w.w_id) AS sum_d_ytd
    FROM warehouse w
) t
WHERE t.w_ytd <> t.sum_d_ytd;

-- Condition 2: For each district, D_NEXT_O_ID - 1 = max(o_id) = max(no_o_id).
SELECT 'COND2 violations: ' || COUNT(*)
FROM district d
WHERE d.d_next_o_id - 1 <>
          (SELECT MAX(o.o_id) FROM oorder o
            WHERE o.o_w_id = d.d_w_id AND o.o_d_id = d.d_id)
   OR d.d_next_o_id - 1 <>
          (SELECT MAX(n.no_o_id) FROM new_order n
            WHERE n.no_w_id = d.d_w_id AND n.no_d_id = d.d_id);

-- Condition 3: For each district,
--   max(no_o_id) - min(no_o_id) + 1 = count(new_order rows in that district).
SELECT 'COND3 violations: ' || COUNT(*)
FROM (
    SELECT n.no_w_id,
           n.no_d_id,
           MAX(n.no_o_id) - MIN(n.no_o_id) + 1 AS range_count,
           COUNT(*) AS row_count
    FROM new_order n
    GROUP BY n.no_w_id, n.no_d_id
) t
WHERE t.range_count <> t.row_count;

-- Condition 4: For each district, sum(o_ol_cnt) = count(order_line rows).
SELECT 'COND4 violations: ' || COUNT(*)
FROM (
    SELECT o.o_w_id,
           o.o_d_id,
           SUM(o.o_ol_cnt) AS sum_ol_cnt,
           (SELECT COUNT(*) FROM order_line ol
             WHERE ol.ol_w_id = o.o_w_id AND ol.ol_d_id = o.o_d_id) AS ol_rows
    FROM oorder o
    GROUP BY o.o_w_id, o.o_d_id
) t
WHERE t.sum_ol_cnt <> t.ol_rows;
