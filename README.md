# Biogas Plant Operations: SQL Analysis (MySQL)

A SQL project that analyses production, downtime and unit economics across three compressed biogas (CBG) plants. The questions come from work I did as an operations executive at an RNG/biogas company: how well is each plant using its capacity, what is causing downtime, and what does one kilogram of CBG cost to produce?

> **Note on the data:** the dataset is synthetic. I generated it to mirror how plant data is structured (daily production, downtime logs, cost ledger, carbon credits), so the absolute numbers illustrate the method and do not describe a real plant.

**Tools:** MySQL 8.0+ (CTEs and window functions are required) · MySQL Workbench · Python (data generation only)

## Data model

Six tables, linked by `plant_id`. `downtime_events` also links to `equipment` through `equipment_id`.

| Table | Rows | What it holds |
|---|---:|---|
| `plants` | 3 | Plant name, state, design capacity (kg CBG/day) |
| `equipment` | 21 | Digesters, compressor, scrubber, gas holder, etc. |
| `daily_production` | 1,095 | Feedstock, biogas, methane %, CBG output, uptime, one row per plant per day |
| `downtime_events` | 56 | Outage date, equipment, hours lost, cause |
| `cost_ledger` | 227 | Monthly OPEX and CAPEX by cost head (INR) |
| `carbon_credits` | 36 | Monthly tCO2e avoided and credit price (INR) |

The script adds primary keys, foreign keys, a unique constraint (one production record per plant per day), indexes, and check constraints (for example, uptime between 0 and 24 hours).

## How to run

1. In MySQL Workbench, import the six CSV files from `data/` into a schema called `biogas` (right-click a table → **Table Data Import Wizard**). Import `plants` and `equipment` first.
2. Open `sql/SQL_CNG_Project.sql` and run **Part 1 (Setup)** once. It fixes column types and adds the keys and constraints.
3. Run **Part 2** to check the load. Expected row counts: 3, 21, 1095, 56, 227, 36.
4. Run the seven queries in **Part 3** one at a time. Select a query and press `Ctrl+Enter`.

Part 1 fails if run a second time, because the keys already exist.

## Queries

| # | Question | Techniques |
|---|---|---|
| Q1 | Which plant makes the best use of its capacity? | Joins, aggregates, ratios |
| Q2 | What is the monthly trend, month-over-month change and 3-month moving average? | CTE, `LAG`, window frames |
| Q3 | Which downtime causes cost the most hours? | CTE, running total with `SUM() OVER`, share of total |
| Q4 | Which equipment fails most in each plant? | Multi-table join, `RANK() OVER (PARTITION BY …)` |
| Q5 | What is OPEX per kg CBG, and how much do carbon credits offset? | Multiple CTEs, `CASE` aggregation, `NULLIF` |
| Q6 | Which days had unusually low output? | Rolling 30-day window, z-score |
| Q7 | Do high-downtime months produce less? | `LEFT JOIN`, `COALESCE`, `NTILE` |

Query output is saved as CSV in `results/`.

## Results

**Plant scorecard (Q1)**

| Plant | CBG (tonnes) | Capacity utilisation | Availability | Avg methane |
|---|---:|---:|---:|---:|
| Green Valley CBG | 837.5 | 57.4% | 99.8% | 55.06% |
| Malwa Renewables | 1,046.7 | 57.4% | 97.3% | 55.83% |
| Sahyadri BioEnergy | 596.3 | 54.5% | 98.1% | 54.04% |

**Downtime by cause (Q3)**

| Cause | Events | Hours lost | Share | Cumulative |
|---|---:|---:|---:|---:|
| Mechanical | 17 | 115.0 | 26.8% | 26.8% |
| Feedstock | 12 | 101.2 | 23.6% | 50.4% |
| Electrical | 12 | 95.9 | 22.4% | 72.8% |
| Process | 8 | 62.2 | 14.5% | 87.3% |
| Planned Maintenance | 7 | 54.4 | 12.7% | 100.0% |

**Unit economics (Q5)**

| Plant | OPEX (₹/kg CBG) | Carbon credits (₹/kg CBG) |
|---|---:|---:|
| Malwa Renewables | 45.33 | 3.42 |
| Sahyadri BioEnergy | 47.57 | 3.19 |
| Green Valley CBG | 48.67 | 3.23 |

**Downtime vs output (Q7)**

| Downtime quartile | Avg hours lost / month | Avg daily uptime (h) | Avg CBG (tonnes / month) |
|---:|---:|---:|---:|
| 1 (lowest) | 0.0 | 24.00 | 69.4 |
| 2 | 3.4 | 23.89 | 71.4 |
| 3 | 14.6 | 23.52 | 72.2 |
| 4 (highest) | 29.7 | 23.00 | 62.6 |

## Findings

- **No single cause dominates downtime.** Mechanical failures lead with 26.8% of lost hours, but Feedstock and Electrical are close behind, and the top three causes together account for 72.8%. Fixing one category would not remove most of the loss.
- **Malwa is the cheapest plant per kg** at ₹45.33 and the largest by volume. Green Valley is the most expensive at ₹48.67.
- **Carbon credits are a small offset.** They cover about ₹3.2–3.4 per kg, roughly 7% of OPEX per kg, so they supplement the economics and do not drive them.
- **Weak spots differ by plant.** At Malwa, the gas holder (6 failures, 57.7 h) and primary digester (7 failures, 54.0 h) are the main problems. At Sahyadri, the primary digester leads (5 failures, 44.6 h). Green Valley had only one unplanned failure all year.
- **Output runs low through winter and rebounds in March.** From December to February all three plants sit below their autumn levels, with February the weakest month at every plant. March then jumps 23–30% month over month (Q2).
- **Low-output days line up with lost uptime.** All 15 flagged days (Q6, z-score below −2) had 18 hours of uptime or less, and the worst was Sahyadri on 2025-12-14 (z = −5.87).
- **The highest-downtime months produced the least CBG** (62.6 tonnes vs 69–72). Quartiles 1 to 3 are not in a clean order, because winter also lowers output in this dataset. Downtime is not the only driver, and a fuller analysis would control for month.

## Limitations

- The data is synthetic, and the winter dip is a built-in feature of the generator.
- Q7 compares plant-months across only three plants, so treat it as directional.
- Q3 includes planned maintenance as a cause, while Q4 excludes it, because a scheduled stop is not a failure.

## Repository layout

```
sql/SQL_CNG_Project.sql        setup, checks and the seven queries
data/                          the six source tables as CSV
results/                       output of each query (q1 to q7)
data_generator/                Python script that produced the data (fixed seed)
```

`data_generator/seed.py` rebuilds the CSVs exactly. The CSVs in `data/` were exported from the SQLite database it creates (`python seed.py`); the analysis itself runs in MySQL.

## Author

Shreyas Patil: mechanical engineer moving into business analytics (MSc Business Analytics, Dublin City University). Background in biogas/RNG plant operations with SAP, Power BI, SQL and SCADA.
