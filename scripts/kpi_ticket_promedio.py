"""KPI Ticket Promedio: SUM(total_amount) / COUNT(pedidos), mismo filtro que Ventas.

Salida: dw/kpi_ticket_mensual.csv  (mes x canal x provincia)
"""
from _common import connect, save

QUERY = """
SELECT
    d.year_month                                        AS mes,
    ch.name                                             AS canal,
    p.name                                              AS provincia,
    COUNT(*)                                            AS pedidos,
    CAST(SUM(o.total_amount) AS DOUBLE)                 AS ventas,
    CAST(SUM(o.total_amount) AS DOUBLE) / COUNT(*)      AS ticket_promedio
FROM fact_sales_order AS o
JOIN dim_date     AS d  ON d.date_key     = o.date_key
JOIN dim_channel  AS ch ON ch.channel_key = o.channel_key
JOIN dim_province AS p  ON p.province_key = o.province_key
WHERE o.is_sale
GROUP BY ALL
ORDER BY mes, canal, provincia
"""

if __name__ == "__main__":
    con = connect()
    save(con, QUERY, "kpi_ticket_mensual")
    ticket = con.sql("SELECT SUM(total_amount) / COUNT(*) FROM fact_sales_order WHERE is_sale").fetchone()[0]
    print(f"Ticket promedio global: ${float(ticket):,.0f}")
    