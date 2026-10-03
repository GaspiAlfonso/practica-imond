"""Utilidades compartidas por los scripts de KPIs.

Los scripts leen los CSV del data warehouse (carpeta dw/) y escriben el
resultado de cada KPI en dw/kpi_*.csv, listo para conectar al dashboard.

Orden de ejecución:  python run_sql.py   y después   python scripts/<kpi>.py
"""
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
DW_DIR = ROOT / "dw"

TABLES = [
    "dim_date", "dim_channel", "dim_province", "dim_product", "dim_customer",
    "dim_store", "dim_payment_method", "dim_order_status", "dim_traffic",
    "fact_sales_order", "fact_sales_item", "fact_payment", "fact_shipment",
    "fact_web_session", "fact_nps",
]


def connect() -> duckdb.DuckDBPyConnection:
    """Conexión en memoria con una vista por cada CSV de dw/."""
    if not (DW_DIR / "fact_sales_order.csv").exists():
        raise SystemExit("No existe dw/. Primero ejecutá:  python run_sql.py")
    con = duckdb.connect()
    for table in TABLES:
        con.sql(f"CREATE VIEW {table} AS SELECT * FROM read_csv('{(DW_DIR / f'{table}.csv').as_posix()}')")
    return con


def save(con: duckdb.DuckDBPyConnection, query: str, name: str) -> None:
    """Ejecuta la consulta, la guarda en dw/<name>.csv y muestra un resumen."""
    out = DW_DIR / f"{name}.csv"
    con.sql(f"COPY ({query}) TO '{out.as_posix()}' (HEADER)")
    rows = con.sql(f"SELECT COUNT(*) FROM read_csv('{out.as_posix()}')").fetchone()[0]
    print(f"OK  dw/{name}.csv  ({rows} filas)")