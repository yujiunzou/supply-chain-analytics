USE supply_chain;
-- 建立完整的plant table資料
INSERT INTO plants (plant_code)
SELECT plant_code FROM plant_ports
UNION
SELECT plant_code FROM products_per_plant
UNION
SELECT plant_code FROM warehouse_capacities
UNION
SELECT plant_code FROM warehouse_costs
UNION
SELECT plant_code FROM orders;

-- 驗證各資料表筆數
SELECT 'orders' AS table_name, COUNT(*) AS row_count FROM orders
UNION ALL
SELECT 'freight_rates', COUNT(*) FROM freight_rates
UNION ALL
SELECT 'plant_ports', COUNT(*) FROM plant_ports
UNION ALL
SELECT 'products_per_plant', COUNT(*) FROM products_per_plant
UNION ALL
SELECT 'vmi_customers', COUNT(*) FROM vmi_customers
UNION ALL
SELECT 'warehouse_capacities', COUNT(*) FROM warehouse_capacities
UNION ALL
SELECT 'warehouse_costs', COUNT(*) FROM warehouse_costs;

-- 驗證子表中的工廠代碼都存在於 plants
SELECT COUNT(*) AS invalid_order_plants
FROM orders o
LEFT JOIN plants p ON o.plant_code = p.plant_code
WHERE p.plant_code IS NULL;

SELECT COUNT(*) AS invalid_plant_ports
FROM plant_ports pp
LEFT JOIN plants p ON pp.plant_code = p.plant_code
WHERE p.plant_code IS NULL;

SELECT COUNT(*) AS invalid_product_plants
FROM products_per_plant pp
LEFT JOIN plants p ON pp.plant_code = p.plant_code
WHERE p.plant_code IS NULL;

SELECT COUNT(*) AS invalid_vmi_plants
FROM vmi_customers v
LEFT JOIN plants p ON v.plant_code = p.plant_code
WHERE p.plant_code IS NULL;

SELECT COUNT(*) AS invalid_capacity_plants
FROM warehouse_capacities wc
LEFT JOIN plants p ON wc.plant_code = p.plant_code
WHERE p.plant_code IS NULL;

SELECT COUNT(*) AS invalid_cost_plants
FROM warehouse_costs wc
LEFT JOIN plants p ON wc.plant_code = p.plant_code
WHERE p.plant_code IS NULL;