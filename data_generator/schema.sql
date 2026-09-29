-- Biogas / CBG plant operations database (SQLite)
-- Synthetic data. Models 3 plants over 12 months of daily operations.

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS carbon_credits;
DROP TABLE IF EXISTS cost_ledger;
DROP TABLE IF EXISTS downtime_events;
DROP TABLE IF EXISTS daily_production;
DROP TABLE IF EXISTS equipment;
DROP TABLE IF EXISTS plants;

CREATE TABLE plants (
    plant_id        INTEGER PRIMARY KEY,
    plant_name      TEXT NOT NULL,
    state           TEXT NOT NULL,
    design_cbg_kg_day INTEGER NOT NULL,      -- nameplate capacity
    commissioned_on DATE NOT NULL
);

CREATE TABLE equipment (
    equipment_id    INTEGER PRIMARY KEY,
    plant_id        INTEGER NOT NULL REFERENCES plants(plant_id),
    equipment_name  TEXT NOT NULL,
    category        TEXT NOT NULL CHECK (category IN
                    ('Digester','Compressor','Scrubber','Gas Holder','Feed System','CHP/Utilities'))
);

CREATE TABLE daily_production (
    prod_id         INTEGER PRIMARY KEY,
    plant_id        INTEGER NOT NULL REFERENCES plants(plant_id),
    prod_date       DATE NOT NULL,
    feedstock_tons  REAL NOT NULL,
    biogas_nm3      REAL NOT NULL,
    methane_pct     REAL NOT NULL,
    cbg_kg          REAL NOT NULL,
    uptime_hours    REAL NOT NULL CHECK (uptime_hours BETWEEN 0 AND 24),
    power_kwh       REAL NOT NULL,
    UNIQUE (plant_id, prod_date)
);

CREATE TABLE downtime_events (
    event_id        INTEGER PRIMARY KEY,
    plant_id        INTEGER NOT NULL REFERENCES plants(plant_id),
    equipment_id    INTEGER NOT NULL REFERENCES equipment(equipment_id),
    event_date      DATE NOT NULL,
    duration_hours  REAL NOT NULL,
    cause           TEXT NOT NULL CHECK (cause IN
                    ('Mechanical','Electrical','Feedstock','Process','Planned Maintenance'))
);

CREATE TABLE cost_ledger (
    cost_id         INTEGER PRIMARY KEY,
    plant_id        INTEGER NOT NULL REFERENCES plants(plant_id),
    cost_month      TEXT NOT NULL,            -- 'YYYY-MM'
    cost_type       TEXT NOT NULL CHECK (cost_type IN ('CAPEX','OPEX')),
    cost_head       TEXT NOT NULL,
    amount_inr      REAL NOT NULL
);

CREATE TABLE carbon_credits (
    credit_id       INTEGER PRIMARY KEY,
    plant_id        INTEGER NOT NULL REFERENCES plants(plant_id),
    credit_month    TEXT NOT NULL,            -- 'YYYY-MM'
    tco2e_avoided   REAL NOT NULL,
    price_per_tco2e_inr REAL NOT NULL
);

CREATE INDEX idx_prod_plant_date ON daily_production(plant_id, prod_date);
CREATE INDEX idx_down_plant_date ON downtime_events(plant_id, event_date);
CREATE INDEX idx_cost_plant_month ON cost_ledger(plant_id, cost_month);
