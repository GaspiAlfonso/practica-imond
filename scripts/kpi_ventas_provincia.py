"""KPI Ventas por provincia: total_amount agrupado por provincia de la dirección de envío.

Salida: dw/kpi_ventas_provincia.csv  (mes x canal x provincia)
"""
from _common import connect, save

QUERY = """
SELECT
    d.year_month                        AS mes,
    ch.name                             AS canal,
    p.name                              AS provincia,
    p.code                              AS cod_provincia,
    COUNT(*)                            AS pedidos,
    CAST(SUM(o.total_amount) AS DOUBLE) AS ventas
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
    save(con, QUERY, "kpi_ventas_provincia")
    print(con.sql("""
        SELECT provincia, CAST(SUM(ventas) AS BIGINT) AS ventas
        FROM read_csv('dw/kpi_ventas_provincia.csv') GROUP BY 1 ORDER BY 2 DESC
    """))