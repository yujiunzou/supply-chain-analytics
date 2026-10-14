USE supply_chain;

ALTER TABLE orders
ADD CONSTRAINT fk_orders_plant
FOREIGN KEY (plant_code)
REFERENCES plants (plant_code);

ALTER TABLE plant_ports
ADD CONSTRAINT fk_plant_ports_plant
FOREIGN KEY (plant_code)
REFERENCES plants (plant_code);

ALTER TABLE products_per_plant
ADD CONSTRAINT fk_products_per_plant_plant
FOREIGN KEY (plant_code)
REFERENCES plants (plant_code);

ALTER TABLE warehouse_capacities
ADD CONSTRAINT fk_warehouse_capacities_plant
FOREIGN KEY (plant_code)
REFERENCES plants (plant_code);

ALTER TABLE warehouse_costs
ADD CONSTRAINT fk_warehouse_costs_plant
FOREIGN KEY (plant_code)
REFERENCES plants (plant_code);

ALTER TABLE vmi_customers
ADD CONSTRAINT fk_vmi_customers_plant
FOREIGN KEY (plant_code)
REFERENCES plants (plant_code);