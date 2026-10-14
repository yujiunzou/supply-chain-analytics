CREATE DATABASE IF NOT EXISTS supply_chain
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE supply_chain;

-- =====================================================
-- Supply Chain Analytics
-- File: 01_schema.sql
-- Purpose: Create database and table structures
-- =====================================================

CREATE DATABASE IF NOT EXISTS supply_chain
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE supply_chain;


-- =====================================================
-- 1. Plants dimension
-- 工廠主檔，之後從其他資料表整理完整的工廠清單
-- =====================================================

CREATE TABLE IF NOT EXISTS plants (
    plant_code VARCHAR(10) NOT NULL,

    PRIMARY KEY (plant_code)
);


-- =====================================================
-- 2. Plant and port mapping
-- 一間工廠可能對應多個港口
-- =====================================================

CREATE TABLE IF NOT EXISTS plant_ports (
    plant_code VARCHAR(10) NOT NULL,
    port VARCHAR(10) NOT NULL,

    PRIMARY KEY (plant_code, port)
);


-- =====================================================
-- 3. Products available at each plant
-- =====================================================

CREATE TABLE IF NOT EXISTS products_per_plant (
    plant_code VARCHAR(10) NOT NULL,
    product_id VARCHAR(20) NOT NULL,

    PRIMARY KEY (plant_code, product_id)
);


-- =====================================================
-- 4. VMI customer assignments
-- =====================================================

CREATE TABLE IF NOT EXISTS vmi_customers (
    plant_code VARCHAR(10) NOT NULL,
    customer VARCHAR(50) NOT NULL,

    PRIMARY KEY (plant_code, customer)
);


-- =====================================================
-- 5. Warehouse daily capacity
-- 一間工廠一筆產能資料
-- =====================================================

CREATE TABLE IF NOT EXISTS warehouse_capacities (
    plant_code VARCHAR(10) NOT NULL,
    daily_capacity INT NOT NULL,

    PRIMARY KEY (plant_code),

    CONSTRAINT chk_daily_capacity
        CHECK (daily_capacity >= 0)
);


-- =====================================================
-- 6. Warehouse unit cost
-- 一間工廠一筆單位成本資料
-- =====================================================

CREATE TABLE IF NOT EXISTS warehouse_costs (
    plant_code VARCHAR(10) NOT NULL,
    cost_unit DECIMAL(24,16) NOT NULL,

    PRIMARY KEY (plant_code),

    CONSTRAINT chk_cost_unit
        CHECK (cost_unit >= 0)
);


-- =====================================================
-- 7. Carrier freight rates
-- 使用 surrogate key，方便 Power BI 與後續 JOIN
-- =====================================================

CREATE TABLE IF NOT EXISTS freight_rates (
    freight_rate_id INT NOT NULL AUTO_INCREMENT,
    carrier VARCHAR(20) NOT NULL,
    origin_port VARCHAR(10) NOT NULL,
    destination_port VARCHAR(10) NOT NULL,
    min_weight DECIMAL(24,16) NOT NULL,
    max_weight DECIMAL(24,16) NOT NULL,
    service_level VARCHAR(10) NOT NULL,
    min_cost DECIMAL(24,16) NOT NULL,
    rate DECIMAL(24,16) NOT NULL,
    transport_mode VARCHAR(20) NOT NULL,
    transport_days INT NOT NULL,
    carrier_type VARCHAR(20) NOT NULL,

    PRIMARY KEY (freight_rate_id),

    CONSTRAINT uq_freight_rate UNIQUE (
        carrier,
        origin_port,
        destination_port,
        min_weight,
        max_weight,
        service_level,
        transport_mode,
        transport_days
    ),

    CONSTRAINT chk_weight_range
        CHECK (min_weight <= max_weight),

    CONSTRAINT chk_freight_values
        CHECK (
            min_weight >= 0
            AND max_weight >= 0
            AND min_cost >= 0
            AND rate >= 0
            AND transport_days >= 0
        )
);


-- =====================================================
-- 8. Orders
-- =====================================================

CREATE TABLE IF NOT EXISTS orders (
    order_id VARCHAR(20) NOT NULL,
    order_date DATE NOT NULL,
    origin_port VARCHAR(10) NOT NULL,
    carrier VARCHAR(20) NOT NULL,
    transport_days INT NOT NULL,
    service_level VARCHAR(10) NOT NULL,
    ship_ahead_day_count INT NOT NULL,
    ship_late_day_count INT NOT NULL,
    customer VARCHAR(50) NOT NULL,
    product_id VARCHAR(20) NOT NULL,
    plant_code VARCHAR(10) NOT NULL,
    destination_port VARCHAR(10) NOT NULL,
    unit_quantity INT NOT NULL,
    weight DECIMAL(24,16) NOT NULL,
    weight_valid VARCHAR(5) NOT NULL,

    PRIMARY KEY (order_id),

    CONSTRAINT chk_order_values
        CHECK (
            transport_days >= 0
            AND ship_ahead_day_count >= 0
            AND ship_late_day_count >= 0
            AND unit_quantity >= 0
            AND weight >= 0
        ),

    CONSTRAINT chk_weight_valid
        CHECK (weight_valid IN ('True', 'False'))
);