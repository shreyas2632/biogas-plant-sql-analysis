"""Seed the biogas plant database with reproducible synthetic data.

Usage: python seed.py   ->  creates plant.db from schema.sql
"""
import random
import sqlite3
from datetime import date, timedelta
from pathlib import Path

random.seed(42)
HERE = Path(__file__).parent
DB = HERE / "plant.db"

PLANTS = [
    (1, "Green Valley CBG", "Haryana", 4000, "2023-04-01"),
    (2, "Sahyadri BioEnergy", "Maharashtra", 3000, "2023-11-15"),
    (3, "Malwa Renewables", "Punjab", 5000, "2024-06-01"),
]

EQUIPMENT = [
    ("Primary Digester", "Digester"), ("Secondary Digester", "Digester"),
    ("Biogas Compressor", "Compressor"), ("H2S Scrubber", "Scrubber"),
    ("Gas Holder", "Gas Holder"), ("Feed Mixing Pit", "Feed System"),
    ("CHP Unit", "CHP/Utilities"),
]

# per-plant behaviour: (avg feed tons/day, methane baseline %, reliability 0-1)
PROFILE = {1: (95, 55.0, 0.94), 2: (70, 54.0, 0.90), 3: (120, 56.0, 0.87)}

COST_HEADS_OPEX = {
    "Feedstock Procurement": 0.45, "Labour": 0.15, "Power & Utilities": 0.15,
    "Maintenance & Spares": 0.15, "Lab & Compliance": 0.05, "Admin": 0.05,
}
CAUSES = ["Mechanical", "Electrical", "Feedstock", "Process", "Planned Maintenance"]


def daterange(start, end):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)


def main():
    if DB.exists():
        DB.unlink()
    con = sqlite3.connect(DB)
    con.executescript((HERE / "schema.sql").read_text())
    cur = con.cursor()

    cur.executemany("INSERT INTO plants VALUES (?,?,?,?,?)", PLANTS)

    eq_ids = {}
    eid = 1
    for pid, *_ in PLANTS:
        eq_ids[pid] = []
        for name, cat in EQUIPMENT:
            cur.execute("INSERT INTO equipment VALUES (?,?,?,?)", (eid, pid, name, cat))
            eq_ids[pid].append(eid)
            eid += 1

    start, end = date(2025, 9, 1), date(2026, 8, 31)

    for pid, _, _, design, _ in PLANTS:
        feed_avg, ch4_base, reliability = PROFILE[pid]
        for d in daterange(start, end):
            # seasonal effect: colder months reduce digester efficiency
            season = 1.0 - 0.10 * (1 if d.month in (12, 1, 2) else 0)
            downtime_today = 0.0
            # random downtime events
            if random.random() > reliability + 0.045:
                dur = round(random.uniform(1, 14), 1)
                cause = random.choices(CAUSES, weights=[35, 20, 15, 20, 10])[0]
                if cause == "Planned Maintenance":
                    dur = round(random.uniform(4, 10), 1)
                cur.execute(
                    "INSERT INTO downtime_events (plant_id, equipment_id, event_date, duration_hours, cause) VALUES (?,?,?,?,?)",
                    (pid, random.choice(eq_ids[pid]), d.isoformat(), dur, cause),
                )
                downtime_today = dur

            uptime = round(24 - min(downtime_today, 24), 1)
            feed = max(0, random.gauss(feed_avg, feed_avg * 0.08)) * (uptime / 24)
            yield_nm3_per_ton = random.gauss(75, 5) * season
            biogas = feed * yield_nm3_per_ton
            ch4 = min(62, max(48, random.gauss(ch4_base, 1.2)))
            # ~ 1 kg CBG per 1.5 Nm3 methane, 90% upgrading recovery
            cbg = min(design * 1.05, biogas * (ch4 / 100) * 0.9 / 1.5)
            power = uptime * random.gauss(320, 15)
            cur.execute(
                "INSERT INTO daily_production (plant_id, prod_date, feedstock_tons, biogas_nm3, methane_pct, cbg_kg, uptime_hours, power_kwh) VALUES (?,?,?,?,?,?,?,?)",
                (pid, d.isoformat(), round(feed, 2), round(biogas, 1), round(ch4, 2), round(cbg, 1), uptime, round(power, 1)),
            )

        # monthly costs & carbon credits
        m = date(2025, 9, 1)
        while m <= end:
            ym = m.strftime("%Y-%m")
            monthly_opex = design * 30 * random.uniform(24, 30)  # INR
            for head, share in COST_HEADS_OPEX.items():
                cur.execute(
                    "INSERT INTO cost_ledger (plant_id, cost_month, cost_type, cost_head, amount_inr) VALUES (?,?,?,?,?)",
                    (pid, ym, "OPEX", head, round(monthly_opex * share * random.uniform(0.92, 1.08), 0)),
                )
            if random.random() < 0.3:  # occasional capex
                cur.execute(
                    "INSERT INTO cost_ledger (plant_id, cost_month, cost_type, cost_head, amount_inr) VALUES (?,?,?,?,?)",
                    (pid, ym, "CAPEX", random.choice(["Compressor Overhaul", "Digester Lining", "SCADA Upgrade", "Gas Holder Membrane"]),
                     round(random.uniform(8, 40) * 100000, 0)),
                )
            avoided = design * 30 * random.uniform(0.0021, 0.0027)  # tCO2e
            cur.execute(
                "INSERT INTO carbon_credits (plant_id, credit_month, tco2e_avoided, price_per_tco2e_inr) VALUES (?,?,?,?)",
                (pid, ym, round(avoided, 1), round(random.uniform(650, 900), 0)),
            )
            m = (m.replace(day=28) + timedelta(days=4)).replace(day=1)

    con.commit()
    for t in ["plants", "equipment", "daily_production", "downtime_events", "cost_ledger", "carbon_credits"]:
        n = cur.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        print(f"{t:18s} {n:>6d} rows")
    con.close()


if __name__ == "__main__":
    main()
