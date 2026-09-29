-- =====================================================
-- Biogas Plant Operations - SQL Analysis (MySQL 8.0+)
-- Author: Shreyas Patil
--
-- About the data:
-- Synthetic daily operations data for 3 CBG plants,
-- Sep 2025 to Aug 2026. I loaded the six CSV files
-- into MySQL first, then ran this script.
--
-- How to use:
--   Part 1 - set up keys and constraints (run once)
--   Part 2 - quick checks that the load worked
--   Part 3 - the seven analysis queries
-- =====================================================

CREATE DATABASE IF NOT EXISTS biogas;
USE biogas;


-- =====================================================
-- PART 1: SETUP (run this once)
-- =====================================================

-- The import wizard guessed some column types, so I am
-- setting proper types first. Keys can't be added on
-- TEXT columns, and dates need to be real DATE values.

ALTER TABLE plants
    MODIFY plant_id            INT          NOT NULL,
    MODIFY plant_name          VARCHAR(100) NOT NULL,
    MODIFY state               VARCHAR(50)  NOT NULL,
    MODIFY design_cbg_kg_day   INT          NOT NULL,
    MODIFY commissioned_on     DATE         NOT NULL;

ALTER TABLE equipment
    MODIFY equipment_id        INT          NOT NULL,
    MODIFY plant_id            INT          NOT NULL,
    MODIFY equipment_name      VARCHAR(100) NOT NULL,
    MODIFY category            VARCHAR(30)  NOT NULL;

ALTER TABLE daily_production
    MODIFY prod_id             INT          NOT NULL,
    MODIFY plant_id            INT          NOT NULL,
    MODIFY prod_date           DATE         NOT NULL;

ALTER TABLE downtime_events
    MODIFY event_id            INT          NOT NULL,
    MODIFY plant_id            INT          NOT NULL,
    MODIFY equipment_id        INT          NOT NULL,
    MODIFY event_date          DATE         NOT NULL,
    MODIFY cause               VARCHAR(30)  NOT NULL;

ALTER TABLE cost_ledger
    MODIFY cost_id             INT          NOT NULL,
    MODIFY plant_id            INT          NOT NULL,
    MODIFY cost_month          CHAR(7)      NOT NULL,
    MODIFY cost_type           VARCHAR(5)   NOT NULL,
    MODIFY cost_head           VARCHAR(50)  NOT NULL;

ALTER TABLE carbon_credits
    MODIFY credit_id           INT          NOT NULL,
    MODIFY plant_id            INT          NOT NULL,
    MODIFY credit_month        CHAR(7)      NOT NULL;


-- Primary keys: one unique ID per row in every table.
ALTER TABLE plants           ADD PRIMARY KEY (plant_id);
ALTER TABLE equipment        ADD PRIMARY KEY (equipment_id);
ALTER TABLE daily_production ADD PRIMARY KEY (prod_id);
ALTER TABLE downtime_events  ADD PRIMARY KEY (event_id);
ALTER TABLE cost_ledger      ADD PRIMARY KEY (cost_id);
ALTER TABLE carbon_credits   ADD PRIMARY KEY (credit_id);


-- A plant should have only one production record per day,
-- so I am enforcing that. The two indexes speed up the
-- downtime and cost lookups used later.
ALTER TABLE daily_production
    ADD CONSTRAINT uq_plant_day UNIQUE (plant_id, prod_date);

CREATE INDEX idx_down_plant_date  ON downtime_events (plant_id, event_date);
CREATE INDEX idx_cost_plant_month ON cost_ledger (plant_id, cost_month);


-- Foreign keys: every record must point to a real plant
-- (and downtime events to a real piece of equipment).
-- This keeps the data consistent across tables.
ALTER TABLE equipment
    ADD CONSTRAINT fk_equip_plant
    FOREIGN KEY (plant_id) REFERENCES plants (plant_id);

ALTER TABLE daily_production
    ADD CONSTRAINT fk_prod_plant
    FOREIGN KEY (plant_id) REFERENCES plants (plant_id);

ALTER TABLE downtime_events
    ADD CONSTRAINT fk_down_plant
    FOREIGN KEY (plant_id)     REFERENCES plants (plant_id),
    ADD CONSTRAINT fk_down_equip
    FOREIGN KEY (equipment_id) REFERENCES equipment (equipment_id);

ALTER TABLE cost_ledger
    ADD CONSTRAINT fk_cost_plant
    FOREIGN KEY (plant_id) REFERENCES plants (plant_id);

ALTER TABLE carbon_credits
    ADD CONSTRAINT fk_carbon_plant
    FOREIGN KEY (plant_id) REFERENCES plants (plant_id);


-- Data quality rules: block values that make no sense
-- (for example, more than 24 hours of uptime in a day).
ALTER TABLE daily_production
    ADD CONSTRAINT chk_uptime CHECK (uptime_hours BETWEEN 0 AND 24);

ALTER TABLE cost_ledger
    ADD CONSTRAINT chk_cost_type CHECK (cost_type IN ('CAPEX', 'OPEX'));

ALTER TABLE downtime_events
    ADD CONSTRAINT chk_cause CHECK (cause IN
        ('Mechanical', 'Electrical', 'Feedstock', 'Process', 'Planned Maintenance'));


-- =====================================================
-- PART 2: CHECKS
-- =====================================================

-- Row counts after import. Expected: 3, 21, 1095, 56, 227, 36.
SELECT 'plants'           AS table_name, COUNT(*) AS row_count FROM plants
UNION ALL SELECT 'equipment',        COUNT(*) FROM equipment
UNION ALL SELECT 'daily_production', COUNT(*) FROM daily_production
UNION ALL SELECT 'downtime_events',  COUNT(*) FROM downtime_events
UNION ALL SELECT 'cost_ledger',      COUNT(*) FROM cost_ledger
UNION ALL SELECT 'carbon_credits',   COUNT(*) FROM carbon_credits;

-- List of all keys and constraints that were created.
SELECT table_name, constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'biogas'
ORDER BY table_name, constraint_type;

-- Full table definition, to confirm PK, unique, FK and check rules.
SHOW CREATE TABLE daily_production;


-- =====================================================
-- PART 3: ANALYSIS QUERIES
-- (run one at a time)
-- =====================================================

-- -----------------------------------------------------
-- Q1. Plant scorecard
-- Which plant makes the most use of its capacity, and
-- how do uptime and gas yield compare across plants?
-- -----------------------------------------------------
SELECT
    p.plant_name,
    ROUND(SUM(d.cbg_kg) / 1000.0, 1)                       AS cbg_tonnes,
    ROUND(AVG(d.cbg_kg) * 100.0 / p.design_cbg_kg_day, 1)  AS capacity_utilisation_pct,
    ROUND(AVG(d.uptime_hours) * 100.0 / 24, 1)             AS availability_pct,
    ROUND(SUM(d.biogas_nm3) / SUM(d.feedstock_tons), 1)    AS biogas_nm3_per_ton,
    ROUND(AVG(d.methane_pct), 2)                           AS avg_methane_pct
FROM plants p
JOIN daily_production d ON d.plant_id = p.plant_id
GROUP BY p.plant_id, p.plant_name, p.design_cbg_kg_day
ORDER BY capacity_utilisation_pct DESC;


-- -----------------------------------------------------
-- Q2. Monthly production trend
-- Monthly CBG output per plant, the change from the
-- previous month, and a 3-month moving average to
-- smooth out the ups and downs.
-- -----------------------------------------------------
WITH monthly AS (
    -- Roll daily production up to one row per plant per month
    SELECT
        p.plant_name,
        DATE_FORMAT(d.prod_date, '%Y-%m') AS month,
        SUM(d.cbg_kg)                     AS cbg_kg
    FROM daily_production d
    JOIN plants p ON p.plant_id = d.plant_id
    GROUP BY p.plant_name, DATE_FORMAT(d.prod_date, '%Y-%m')
)
SELECT
    plant_name,
    month,
    ROUND(cbg_kg / 1000.0, 1) AS cbg_tonnes,
    -- LAG() looks at last month's value for the same plant
    ROUND(100.0 * (cbg_kg - LAG(cbg_kg) OVER w) / LAG(cbg_kg) OVER w, 1) AS mom_change_pct,
    -- average of the current month and the two before it
    ROUND(AVG(cbg_kg) OVER (PARTITION BY plant_name ORDER BY month
                            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) / 1000.0, 1) AS ma3_tonnes
FROM monthly
WINDOW w AS (PARTITION BY plant_name ORDER BY month)
ORDER BY plant_name, month;


-- -----------------------------------------------------
-- Q3. Downtime Pareto
-- Which causes of downtime cost us the most hours?
-- The cumulative % shows how quickly the top causes
-- add up to the total.
-- -----------------------------------------------------
WITH by_cause AS (
    -- Total events and hours lost for each cause
    SELECT
        cause,
        COUNT(*)                      AS events,
        ROUND(SUM(duration_hours), 1) AS hours_lost
    FROM downtime_events
    GROUP BY cause
),
ranked AS (
    -- Share of the total, plus a running total from biggest to smallest
    SELECT
        cause,
        events,
        hours_lost,
        100.0 * hours_lost / SUM(hours_lost) OVER ()             AS share_pct,
        100.0 * SUM(hours_lost) OVER (ORDER BY hours_lost DESC
                                      ROWS UNBOUNDED PRECEDING)
              / SUM(hours_lost) OVER ()                          AS cumulative_pct
    FROM by_cause
)
SELECT
    cause,
    events,
    hours_lost,
    ROUND(share_pct, 1)      AS share_pct,
    ROUND(cumulative_pct, 1) AS cumulative_pct
FROM ranked
ORDER BY hours_lost DESC;


-- -----------------------------------------------------
-- Q4. Equipment reliability
-- The two equipment items with the most breakdown hours
-- in each plant. Planned maintenance is left out because
-- it is scheduled, not a failure.
-- -----------------------------------------------------
WITH eq_stats AS (
    SELECT
        p.plant_name,
        e.equipment_name,
        e.category,
        COUNT(*)                       AS failures,
        ROUND(SUM(x.duration_hours),1) AS hours_down,
        ROUND(AVG(x.duration_hours),1) AS avg_repair_hrs
    FROM downtime_events x
    JOIN equipment e ON e.equipment_id = x.equipment_id
    JOIN plants p    ON p.plant_id     = x.plant_id
    WHERE x.cause <> 'Planned Maintenance'
    GROUP BY p.plant_name, e.equipment_id, e.equipment_name, e.category
),
ranked AS (
    -- Rank equipment within each plant, worst first
    SELECT
        eq_stats.*,
        RANK() OVER (PARTITION BY plant_name ORDER BY hours_down DESC) AS rnk
    FROM eq_stats
)
SELECT
    plant_name, equipment_name, category,
    failures, hours_down, avg_repair_hrs, rnk
FROM ranked
WHERE rnk <= 2
ORDER BY plant_name, rnk;


-- -----------------------------------------------------
-- Q5. Unit economics
-- What does it cost to produce 1 kg of CBG at each plant,
-- and how much of that do carbon credits cover?
-- (opex in crore INR, capex and carbon revenue in lakh INR)
-- -----------------------------------------------------
WITH prod AS (
    -- Total gas produced per plant
    SELECT plant_id, SUM(cbg_kg) AS cbg_kg
    FROM daily_production
    GROUP BY plant_id
),
cost AS (
    -- Split total spend into running cost (OPEX) and investment (CAPEX)
    SELECT
        plant_id,
        SUM(CASE WHEN cost_type = 'OPEX'  THEN amount_inr ELSE 0 END) AS opex_inr,
        SUM(CASE WHEN cost_type = 'CAPEX' THEN amount_inr ELSE 0 END) AS capex_inr
    FROM cost_ledger
    GROUP BY plant_id
),
carbon AS (
    -- Carbon credit revenue = tonnes avoided x price for that month
    SELECT
        plant_id,
        SUM(tco2e_avoided)                       AS tco2e,
        SUM(tco2e_avoided * price_per_tco2e_inr) AS carbon_revenue_inr
    FROM carbon_credits
    GROUP BY plant_id
)
SELECT
    p.plant_name,
    ROUND(pr.cbg_kg / 1000.0, 0)                           AS cbg_tonnes,
    ROUND(c.opex_inr / 1e7, 2)                             AS opex_cr_inr,
    -- NULLIF avoids a divide-by-zero error if a plant had no output
    ROUND(c.opex_inr / NULLIF(pr.cbg_kg, 0), 2)            AS opex_inr_per_kg,
    ROUND(c.capex_inr / 1e5, 1)                            AS capex_lakh_inr,
    ROUND(cb.carbon_revenue_inr / 1e5, 1)                  AS carbon_revenue_lakh_inr,
    ROUND(cb.carbon_revenue_inr / NULLIF(pr.cbg_kg, 0), 2) AS carbon_inr_per_kg
FROM plants p
JOIN prod   pr ON pr.plant_id = p.plant_id
JOIN cost   c  ON c.plant_id  = p.plant_id
JOIN carbon cb ON cb.plant_id = p.plant_id
ORDER BY opex_inr_per_kg;


-- -----------------------------------------------------
-- Q6. Unusual low-output days
-- Flags days when output dropped more than 2 standard
-- deviations below the plant's previous 30-day average.
-- MySQL's window functions are used to build the rolling
-- mean and spread, then a z-score for each day.
-- -----------------------------------------------------
WITH rolling AS (
    -- Stats over the 30 days BEFORE each day (today excluded)
    SELECT
        plant_id, prod_date, cbg_kg, uptime_hours,
        AVG(cbg_kg)          OVER w AS mean_30,
        AVG(cbg_kg * cbg_kg) OVER w AS mean_sq_30,
        COUNT(*)             OVER w AS n
    FROM daily_production
    WINDOW w AS (PARTITION BY plant_id ORDER BY prod_date
                 ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING)
),
scored AS (
    -- Standard deviation = sqrt(mean of squares - square of mean).
    -- Only use days with a full 30-day history.
    SELECT
        rolling.*,
        SQRT(GREATEST(mean_sq_30 - mean_30 * mean_30, 0)) AS sd_30
    FROM rolling
    WHERE n >= 30
)
SELECT
    p.plant_name,
    s.prod_date,
    ROUND(s.cbg_kg, 0)                         AS cbg_kg,
    ROUND(s.mean_30, 0)                        AS rolling_mean,
    ROUND((s.cbg_kg - s.mean_30) / s.sd_30, 2) AS z_score,
    s.uptime_hours
FROM scored s
JOIN plants p ON p.plant_id = s.plant_id
WHERE s.sd_30 > 0
  AND (s.cbg_kg - s.mean_30) / s.sd_30 < -2
ORDER BY z_score
LIMIT 15;


-- -----------------------------------------------------
-- Q7. Does downtime hurt output?
-- Groups every plant-month into four buckets by hours
-- lost (1 = least downtime, 4 = most) and compares the
-- average output in each bucket.
-- Note: winter months also lower output in this data,
-- so the pattern is not perfectly clean.
-- -----------------------------------------------------
WITH prod AS (
    -- Monthly output and average daily uptime per plant
    SELECT
        plant_id,
        DATE_FORMAT(prod_date, '%Y-%m') AS month,
        SUM(cbg_kg)                     AS cbg_kg,
        AVG(uptime_hours)               AS avg_uptime
    FROM daily_production
    GROUP BY plant_id, DATE_FORMAT(prod_date, '%Y-%m')
),
down AS (
    -- Monthly hours lost to downtime per plant
    SELECT
        plant_id,
        DATE_FORMAT(event_date, '%Y-%m') AS month,
        SUM(duration_hours)              AS hours_lost
    FROM downtime_events
    GROUP BY plant_id, DATE_FORMAT(event_date, '%Y-%m')
),
joined AS (
    -- LEFT JOIN keeps months with no downtime (counted as 0 hours)
    SELECT
        p.plant_id, p.month, p.cbg_kg, p.avg_uptime,
        COALESCE(d.hours_lost, 0) AS hours_lost
    FROM prod p
    LEFT JOIN down d ON d.plant_id = p.plant_id AND d.month = p.month
),
bucketed AS (
    -- NTILE(4) splits the plant-months into four equal groups
    SELECT
        joined.*,
        NTILE(4) OVER (ORDER BY hours_lost) AS downtime_quartile
    FROM joined
)
SELECT
    downtime_quartile              AS quartile_1_low_4_high,
    COUNT(*)                       AS plant_months,
    ROUND(AVG(hours_lost), 1)      AS avg_hours_lost,
    ROUND(AVG(avg_uptime), 2)      AS avg_daily_uptime,
    ROUND(AVG(cbg_kg) / 1000.0, 1) AS avg_cbg_tonnes
FROM bucketed
GROUP BY downtime_quartile
ORDER BY downtime_quartile;