"""KPI Ventas: SUM(total_amount) de pedidos PAID o FULFILLED.

Salida: dw/kpi_ventas_diario.csv  (día x canal x provincia)
Incluye cantidad de pedidos, para poder calcular el ticket en el dashboard
como SUM(ventas) / SUM(pedidos).
"""
from _common import connect, save

QUERY = """
SELECT
    d.full_date                         AS fecha,
    d.year_month                        AS mes,
    ch.name                             AS canal,
    p.name                              AS provincia,
    COUNT(*)                            AS pedidos,
    CAST(SUM(o.total_amount) AS DOUBLE) AS ventas
FROM fact_sales_order AS o
JOIN dim_date     AS d  ON d.date_key     = o.date_key
JOIN dim_channel  AS ch ON ch.channel_key = o.channel_key
JOIN dim_province AS p  ON p.province_key = o.province_key
WHERE o.is_sale
GROUP BY ALL
ORDER BY fecha, canal, provincia
"""

if __name__ == "__main__":
    con = connect()
    save(con, QUERY, "kpi_ventas_diario")
    total, pedidos = con.sql("SELECT SUM(ventas), SUM(pedidos) FROM read_csv('dw/kpi_ventas_diario.csv')").fetchone()
    print(f"Ventas totales: ${total:,.0f}  |  Pedidos: {pedidos:,}")