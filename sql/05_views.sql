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