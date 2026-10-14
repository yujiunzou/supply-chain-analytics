-- =====================================================
# 1.工廠每日產能 利用率
# WhCapacities 的容量單位是 number of orders per day
USE supply_chain;

select o.order_date, o.plant_code, count(o.order_id) as order_count,
		sum(o.unit_quantity) as total_units, w.daily_capacity,
        round(count(o.order_id) / NULLIF(w.daily_capacity, 0) *100, 2 )as capacity_utilization_pct
from orders o 
left join warehouse_capacities w
on o.plant_code = w.plant_code
group by o.order_date, o.plant_code, w.daily_capacity;
-- =====================================================
# 2.顧客需求集中度分析
SELECT
    customer,
    COUNT(order_id) AS order_count,
    ROUND(COUNT(order_id)/ SUM(COUNT(order_id)) OVER ()* 100,2) AS order_share_pct,
    SUM(unit_quantity) AS total_units,
    ROUND(SUM(unit_quantity)/ SUM(SUM(unit_quantity)) OVER ()* 100,2) AS unit_share_pct,
    ROUND(SUM(weight), 2) AS total_weight
FROM orders
GROUP BY customer
ORDER BY order_share_pct DESC;
-- =====================================================
# 3.各工廠預估倉儲成本分析
select o.plant_code, count(o.order_id) as order_count,
		sum(o.unit_quantity) as total_units, round(wc.cost_unit, 2) as warehouse_cost_per_unit,
        round(sum(o.unit_quantity*wc.cost_unit), 2 )as estimated_warehouse_cost
from orders o 
left join warehouse_costs wc
on o.plant_code = wc.plant_code
group by o.plant_code, wc.cost_unit;
-- =====================================================
# 4.訂單的運費費率覆蓋率
SELECT
o.order_id,o.carrier,o.origin_port,o.destination_port,
o.service_level,o.transport_days,round(o.weight,2)as weight,
round(f.min_weight,2) as min_weight,round(f.max_weight,2)as maz_weight,f.transport_mode,
round(f.rate,2) as rate,round(f.min_cost,2)as min_cost,
CASE WHEN f.rate IS NOT NULL THEN 'MATCHED'ELSE 'UNMATCHED'END AS rate_match_status
from orders o
LEFT JOIN freight_rates f
    ON o.carrier = f.carrier
   AND o.origin_port = f.origin_port
   AND o.destination_port = f.destination_port
   AND o.service_level = f.service_level
   AND o.transport_days = f.transport_days
   AND o.weight >= f.min_weight
   AND o.weight <= f.max_weight
ORDER BY o.order_id;

##計算配對數量
SELECT
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT CASE WHEN f.rate IS NOT NULL THEN o.order_id END) AS matched_orders,
    COUNT(DISTINCT CASE WHEN f.rate IS NULL THEN o.order_id END) AS unmatched_orders,
    ROUND(COUNT(DISTINCT CASE WHEN f.rate IS NOT NULL THEN o.order_id END) / COUNT(DISTINCT o.order_id) * 100,2) AS coverage_rate_pct
FROM orders o
LEFT JOIN freight_rates f
    ON o.carrier = f.carrier
   AND o.origin_port = f.origin_port
   AND o.destination_port = f.destination_port
   AND o.service_level = f.service_level
   AND o.transport_days = f.transport_days
   AND o.weight >= f.min_weight
   AND o.weight <= f.max_weight;
   
## 2224筆無配對的詳細內容
SELECT
    o.service_level,
    o.carrier,
    COUNT(*) AS unmatched_orders
FROM orders o
WHERE NOT EXISTS (
    SELECT 1
    FROM freight_rates f
    WHERE o.carrier = f.carrier
      AND o.origin_port = f.origin_port
      AND o.destination_port = f.destination_port
      AND o.service_level = f.service_level
      AND o.transport_days = f.transport_days
      AND o.weight >= f.min_weight
      AND o.weight <= f.max_weight
)
GROUP BY
    o.service_level,
    o.carrier
ORDER BY unmatched_orders DESC;

## 檢查是否service level為 Customer Referred Freight (crf) 皆unmatced
SELECT
    COUNT(DISTINCT o.order_id) AS crf_total_orders,
    COUNT(DISTINCT CASE
        WHEN f.rate IS NOT NULL THEN o.order_id
    END) AS crf_matched_orders
FROM orders o
LEFT JOIN freight_rates f
    ON o.carrier = f.carrier
   AND o.origin_port = f.origin_port
   AND o.destination_port = f.destination_port
   AND o.service_level = f.service_level
   AND o.transport_days = f.transport_days
   AND o.weight >= f.min_weight
   AND o.weight <= f.max_weight
WHERE o.service_level = 'CRF';

## 總結配對
USE supply_chain;
WITH order_match_status AS (
	SELECT o.order_id, o.service_level,
        CASE WHEN EXISTS (
			SELECT 1
			FROM freight_rates f
			WHERE o.carrier = f.carrier
			AND o.origin_port = f.origin_port
			AND o.destination_port = f.destination_port
			AND o.service_level = f.service_level
			AND o.transport_days = f.transport_days
			AND o.weight >= f.min_weight
			AND o.weight <= f.max_weight)THEN 1 ELSE 0 END AS is_matched
			FROM orders o)
SELECT
    COUNT(*) AS total_orders,
    SUM(CASE WHEN service_level = 'CRF' THEN 1 ELSE 0 END) AS crf_orders,
    SUM(CASE WHEN service_level <> 'CRF' THEN 1 ELSE 0 END) AS rate_eligible_orders,
    SUM(CASE WHEN service_level <> 'CRF'AND is_matched = 1 THEN 1 ELSE 0 END) AS matched_orders,
    SUM(CASE WHEN service_level <> 'CRF'  AND is_matched = 0 THEN 1 ELSE 0 END) AS unmatched_dtd_orders,
    ROUND(SUM(CASE WHEN service_level <> 'CRF' AND is_matched = 1 THEN 1 ELSE 0 END)
		/ NULLIF(SUM(CASE WHEN service_level <> 'CRF' THEN 1 ELSE 0  END),0) * 100,2) AS adjusted_coverage_rate_pct,
    SUM(CASE WHEN service_level = 'CRF'AND is_matched = 1 THEN 1 ELSE 0 END) AS incorrectly_matched_crf_orders
FROM order_match_status;
-- =====================================================

# 5.計算可配對訂單的運費成本
WITH rate_candidates AS (
    SELECT o.order_id,o.carrier, o.origin_port, o.destination_port, o.weight,
		f.transport_mode,f.rate,f.min_cost,
        -- 運費取「重量 × 費率」與「最低收費」中較高者
        GREATEST(o.weight * f.rate, f.min_cost) AS candidate_freight_cost
    FROM orders o
    JOIN freight_rates f
        ON o.carrier = f.carrier
       AND o.origin_port = f.origin_port
       AND o.destination_port = f.destination_port
       AND o.service_level = f.service_level
       AND o.transport_days = f.transport_days
       AND o.weight >= f.min_weight
       AND o.weight <= f.max_weight
    -- 排除顧客自行安排運輸的訂單
    WHERE o.service_level <> 'CRF'
),

best_rate_per_order AS (
    SELECT order_id,carrier, origin_port,destination_port,
	-- 若同一訂單符合多筆費率，選擇最低成本
	MIN(candidate_freight_cost) AS freight_cost
    FROM rate_candidates
    GROUP BY order_id, carrier, origin_port,destination_port
)

SELECT
    COUNT(*) AS matched_orders,
    ROUND(SUM(freight_cost), 2) AS calculable_freight_cost,
    ROUND(AVG(freight_cost), 2) AS avg_freight_cost_per_order,
    ROUND(MIN(freight_cost), 2) AS min_freight_cost,
    ROUND(MAX(freight_cost), 2) AS max_freight_cost
FROM best_rate_per_order;
-- =====================================================

# 6.找出未配對DTD訂單的主要費率缺口
WITH unmatched_orders AS (
    SELECT o.order_id, o.carrier, o.origin_port, o.destination_port,
        o.service_level,o.transport_days,o.weight
    FROM orders o
    WHERE o.service_level <> 'CRF'
      AND NOT EXISTS (
          SELECT 1
          FROM freight_rates f
          WHERE o.carrier = f.carrier
            AND o.origin_port = f.origin_port
            AND o.destination_port = f.destination_port
            AND o.service_level = f.service_level
            AND o.transport_days = f.transport_days
            AND o.weight >= f.min_weight
            AND o.weight <= f.max_weight
      )
),

classified_gaps AS (
    SELECT u.*,
        CASE
            -- 所有條件都有，只差重量未落入任何區間
            WHEN EXISTS (
                SELECT 1
                FROM freight_rates f
                WHERE u.carrier = f.carrier
                  AND u.origin_port = f.origin_port
                  AND u.destination_port = f.destination_port
                  AND u.service_level = f.service_level
                  AND u.transport_days = f.transport_days)
            THEN 'WEIGHT_RANGE_GAP'

            -- 路線及服務存在，但運輸天數不同
            WHEN EXISTS (
                SELECT 1
                FROM freight_rates f
                WHERE u.carrier = f.carrier
                  AND u.origin_port = f.origin_port
                  AND u.destination_port = f.destination_port
                  AND u.service_level = f.service_level)
            THEN 'TRANSPORT_DAYS_MISMATCH'

            -- 承運商與路線存在，但服務等級不同
            WHEN EXISTS (
                SELECT 1
                FROM freight_rates f
                WHERE u.carrier = f.carrier
                  AND u.origin_port = f.origin_port
                  AND u.destination_port = f.destination_port)
            THEN 'SERVICE_LEVEL_MISMATCH'

            -- 承運商存在，但沒有該路線
            WHEN EXISTS (
                SELECT 1
                FROM freight_rates f
                WHERE u.carrier = f.carrier)
            THEN 'ROUTE_NOT_COVERED'
            ELSE 'CARRIER_NOT_FOUND'
        END AS gap_reason

    FROM unmatched_orders u
)

SELECT gap_reason,COUNT(*) AS unmatched_orders,
	   ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100,2) AS share_of_unmatched_pct
FROM classified_gaps
GROUP BY gap_reason
ORDER BY unmatched_orders DESC;

## 找出最需要補費率的路線
WITH unmatched_orders AS (
    SELECT
        o.order_id,o.carrier,o.origin_port,o.destination_port,
        o.service_level,o.transport_days,o.weight
    FROM orders o
    WHERE o.service_level <> 'CRF'
      AND NOT EXISTS (
          SELECT 1
          FROM freight_rates f
          WHERE o.carrier = f.carrier
            AND o.origin_port = f.origin_port
            AND o.destination_port = f.destination_port
            AND o.service_level = f.service_level
            AND o.transport_days = f.transport_days
            AND o.weight >= f.min_weight
            AND o.weight <= f.max_weight
      )
)

SELECT
    carrier,origin_port,destination_port,service_level,transport_days,
    COUNT(*) AS unmatched_orders,
    ROUND(MIN(weight), 2) AS min_unmatched_weight,
    ROUND(MAX(weight), 2) AS max_unmatched_weight,
    ROUND(AVG(weight), 2) AS avg_unmatched_weight
FROM unmatched_orders
GROUP BY carrier,origin_port,destination_port,service_level,transport_days
ORDER BY unmatched_orders DESC;
