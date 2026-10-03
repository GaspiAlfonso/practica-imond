"""KPI Ranking mensual por producto: SUM(line_total) por producto y mes.

Salida: dw/kpi_ranking_producto_mensual.csv  (mes x canal x provincia x producto)
`ranking_mes` es la posición del producto en el mes considerando todos los canales y provincias.
Con filtros activos, el dashboard puede reordenar por `ventas_items` y mostrar el top N.
Nota: line_total no incluye IVA ni envío (por eso no coincide con KPI Ventas).
"""
from _common import connect, save

QUERY = """
WITH base AS (
    SELECT d.year_month AS mes, ch.name AS canal, pr.name AS provincia,
           p.name AS producto, p.category AS categoria,
           SUM(i.quantity) AS unidades,
           CAST(SUM(i.line_total) AS DOUBLE) AS ventas_items
    FROM fact_sales_item AS i
    JOIN dim_date     AS d  ON d.date_key     = i.date_key
    JOIN dim_channel  AS ch ON ch.channel_key = i.channel_key
    JOIN dim_province AS pr ON pr.province_key = i.province_key
    JOIN dim_product  AS p  ON p.product_key  = i.product_key
    WHERE i.is_sale
    GROUP BY ALL
),
ranking AS (
    SELECT mes, producto,
           RANK() OVER (PARTITION BY mes ORDER BY SUM(ventas_items) DESC) AS ranking_mes
    FROM base GROUP BY mes, producto
)
SELECT b.*, r.ranking_mes
FROM base AS b
JOIN ranking AS r USING (mes, producto)
ORDER BY b.mes, r.ranking_mes, b.canal, b.provincia
"""

if __name__ == "__main__":
    con = connect()
    save(con, QUERY, "kpi_ranking_producto_mensual")
    print(con.sql("""
        SELECT mes, producto, CAST(SUM(ventas_items) AS BIGINT) AS ventas_items, MIN(ranking_mes) AS ranking
        FROM read_csv('dw/kpi_ranking_producto_mensual.csv')
        GROUP BY mes, producto ORDER BY mes DESC, ranking LIMIT 6
    """))