USE supply_chain;

# View 1：工廠績效
CREATE OR REPLACE VIEW vw_plant_performance AS
SELECT
    o.order_date,o.plant_code,
    COUNT(o.order_id) AS order_count,
    SUM(o.unit_quantity) AS total_units,
    wc.daily_capacity,
    ROUND( COUNT(o.order_id)/ NULLIF(wc.daily_capacity, 0)* 100,2) AS historical_load_vs_capacity_pct,
    wcost.cost_unit AS warehouse_cost_per_unit,
    ROUND(SUM(o.unit_quantity) * wcost.cost_unit,2) AS estimated_warehouse_cost

FROM orders o
LEFT JOIN warehouse_capacities wc
    ON o.plant_code = wc.plant_code
LEFT JOIN warehouse_costs wcost
    ON o.plant_code = wcost.plant_code
GROUP BY o.order_date,o.plant_code,wc.daily_capacity,wcost.cost_unit;

-- =========================================================
# View 2: 顧客集中度 Customer concentration
CREATE OR REPLACE VIEW vw_customer_concentration AS
SELECT
    o.customer, COUNT(o.order_id) AS order_count,
    ROUND(COUNT(o.order_id)/ NULLIF((SELECT COUNT(*) FROM orders), 0)* 100,2) AS order_share_pct,
    SUM(o.unit_quantity) AS total_units,
    ROUND(SUM(o.unit_quantity)/ NULLIF((SELECT SUM(unit_quantity) FROM orders), 0)* 100,2) AS unit_share_pct,
    ROUND(SUM(o.weight), 2) AS total_weight,
    CASE WHEN exists (select 1 from vmi_customers v where v.customer = o.customer
    ) THEN 'VMI' ELSE 'NON_VMI' END AS customer_type
FROM orders o
GROUP BY o.customer;

-- =========================================================
# View 3: 訂單運費明細 Customer concentration
CREATE OR REPLACE VIEW vw_order_freight_detail AS

SELECT
    o.order_id, o.order_date,o.customer,o.product_id,
    o.plant_code,o.carrier,o.origin_port,o.destination_port,
    o.service_level,o.transport_days,o.unit_quantity,o.weight,
    CASE
        WHEN o.service_level = 'CRF'
            THEN 'NOT_APPLICABLE_CRF'
        WHEN best_rate.order_id IS NOT NULL
            THEN 'MATCHED'
        WHEN EXISTS (
            SELECT 1
            FROM freight_rates f2
            WHERE o.carrier = f2.carrier
              AND o.origin_port = f2.origin_port
              AND o.destination_port = f2.destination_port
              AND o.service_level = f2.service_level
              AND o.transport_days = f2.transport_days)
            THEN 'WEIGHT_RANGE_GAP'
        ELSE 'OTHER_RATE_GAP'
    END AS freight_match_status, best_rate.freight_cost
FROM orders o
LEFT JOIN (
    SELECT o2.order_id, MIN(GREATEST(o2.weight * f.rate, f.min_cost)) AS freight_cost
    FROM orders o2
    JOIN freight_rates f
        ON o2.carrier = f.carrier
       AND o2.origin_port = f.origin_port
       AND o2.destination_port = f.destination_port
       AND o2.service_level = f.service_level
       AND o2.transport_days = f.transport_days
       AND o2.weight >= f.min_weight
       AND o2.weight <= f.max_weight
    WHERE o2.service_level <> 'CRF'
    GROUP BY o2.order_id) AS best_rate
    ON o.order_id = best_rate.order_id;
    
-- =========================================================
# View 4: 訂單運費明細 Customer concentration
USE supply_chain;

CREATE OR REPLACE VIEW vw_freight_optimization AS

WITH current_rate_candidates AS (
    -- 依照訂單目前指定的承運商配對費率
    SELECT
        o.order_id,
        f.carrier AS matched_carrier,
        f.rate,
        f.min_cost,
        GREATEST(
            o.weight * f.rate,
            f.min_cost
        ) AS estimated_freight_cost,

        ROW_NUMBER() OVER (
            PARTITION BY o.order_id
            ORDER BY
                GREATEST(o.weight * f.rate, f.min_cost),
                f.rate,
                f.carrier
        ) AS rate_rank

    FROM orders o
    JOIN freight_rates f
        ON o.carrier = f.carrier
       AND o.origin_port = f.origin_port
       AND o.destination_port = f.destination_port
       AND o.service_level = f.service_level
       AND o.transport_days = f.transport_days
       AND o.weight BETWEEN f.min_weight AND f.max_weight

    WHERE o.service_level <> 'CRF'
),

current_best_rate AS (
    -- 每筆訂單只保留目前承運商的最低成本費率
    SELECT
        order_id,
        matched_carrier,
        rate,
        min_cost,
        estimated_freight_cost
    FROM current_rate_candidates
    WHERE rate_rank = 1
),

unmatched_applicable_orders AS (
    -- 找出排除 CRF 後，目前承運商無法配對費率的訂單
    SELECT o.*
    FROM orders o
    LEFT JOIN current_best_rate c
        ON o.order_id = c.order_id
    WHERE o.service_level <> 'CRF'
      AND c.order_id IS NULL
),

alternative_rate_candidates AS (
    -- 未配對訂單改用其他可用承運商進行配對
    SELECT
        o.order_id,
        f.carrier AS alternative_carrier,
        f.rate AS alternative_rate,
        f.min_cost AS alternative_min_cost,

        GREATEST(
            o.weight * f.rate,
            f.min_cost
        ) AS alternative_freight_cost,

        ROW_NUMBER() OVER (
            PARTITION BY o.order_id
            ORDER BY
                GREATEST(o.weight * f.rate, f.min_cost),
                f.rate,
                f.carrier
        ) AS alternative_rank

    FROM unmatched_applicable_orders o
    JOIN freight_rates f
        ON o.origin_port = f.origin_port
       AND o.destination_port = f.destination_port
       AND o.service_level = f.service_level
       AND o.transport_days = f.transport_days
       AND o.weight BETWEEN f.min_weight AND f.max_weight
),

best_alternative_rate AS (
    -- 每筆訂單只保留成本最低的替代承運商
    SELECT
        order_id,
        alternative_carrier,
        alternative_rate,
        alternative_min_cost,
        alternative_freight_cost
    FROM alternative_rate_candidates
    WHERE alternative_rank = 1
)

SELECT
    o.order_id,
    o.order_date,
    o.plant_code,
    o.customer,
    o.product_id,
    o.carrier AS current_carrier,
    o.origin_port,
    o.destination_port,
    o.service_level,
    o.transport_days,
    o.weight,
    o.unit_quantity,

    c.rate AS current_rate,
    c.min_cost AS current_min_cost,
    c.estimated_freight_cost AS current_freight_cost,

    a.alternative_carrier,
    a.alternative_rate,
    a.alternative_min_cost,
    a.alternative_freight_cost,

    CASE
        WHEN c.order_id IS NOT NULL
            THEN 'CURRENT_CARRIER'
        WHEN a.order_id IS NOT NULL
            THEN 'ALTERNATIVE_CARRIER'
        ELSE 'STILL_UNMATCHED'
    END AS rate_source,

    CASE
        WHEN c.order_id IS NOT NULL
            THEN o.carrier
        WHEN a.order_id IS NOT NULL
            THEN a.alternative_carrier
        ELSE NULL
    END AS final_carrier,

    CASE
        WHEN c.order_id IS NOT NULL
            THEN c.estimated_freight_cost
        WHEN a.order_id IS NOT NULL
            THEN a.alternative_freight_cost
        ELSE NULL
    END AS final_freight_cost

FROM orders o
LEFT JOIN current_best_rate c
    ON o.order_id = c.order_id
LEFT JOIN best_alternative_rate a
    ON o.order_id = a.order_id
WHERE o.service_level <> 'CRF';

-------------------------------------
CREATE OR REPLACE VIEW vw_product_supply_risk AS

WITH product_demand AS (
    SELECT
        product_id,
        COUNT(DISTINCT order_id) AS total_orders,
        SUM(unit_quantity) AS total_units,
        ROUND(SUM(weight), 2) AS total_weight,
        COUNT(DISTINCT customer) AS unique_customers,
        COUNT(DISTINCT plant_code) AS plants_used
    FROM orders
    GROUP BY product_id
),

product_availability AS (
    SELECT
        product_id,
        COUNT(DISTINCT plant_code) AS available_plants
    FROM products_per_plant
    GROUP BY product_id
)

SELECT
    d.product_id,
    d.total_orders,
    d.total_units,
    d.total_weight,
    d.unique_customers,
    d.plants_used,
    COALESCE(a.available_plants, 0) AS available_plants,

    CASE
        WHEN COALESCE(a.available_plants, 0) = 0
            THEN 'No Available Plant'
        WHEN a.available_plants = 1
            THEN 'Single-Plant Dependency'
        WHEN a.available_plants = 2
            THEN 'Two Available Plants'
        ELSE 'Diversified'
    END AS supply_risk,

    CASE
        WHEN COALESCE(a.available_plants, 0) = 0 THEN 1
        WHEN a.available_plants = 1 THEN 2
        WHEN a.available_plants = 2 THEN 3
        ELSE 4
    END AS risk_sort_order

FROM product_demand d
LEFT JOIN product_availability a
    ON d.product_id = a.product_id;