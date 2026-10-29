-- =====================================================================
-- 04_data_marts.sql — Data marts como tablas del warehouse (DuckDB)
-- Todos los indicadores se calculan acá con SQL. Los dashboards
-- solo muestran estas tablas, sin fórmulas propias.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS mart;

-- mart.ventas_diario: ventas y pedidos por día, canal y provincia
CREATE TABLE mart.ventas_diario AS
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
ORDER BY fecha, canal, provincia;

-- mart.ventas_provincia: ventas y pedidos por mes, canal y provincia (para el mapa)
CREATE TABLE mart.ventas_provincia AS
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
ORDER BY mes, canal, provincia;

-- mart.ticket_mensual: ticket promedio ya calculado (ventas / pedidos)
CREATE TABLE mart.ticket_mensual AS
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
ORDER BY mes, canal, provincia;

-- mart.usuarios_activos_diario: usuarios distintos por día y origen (+ fila 'Todos')
CREATE TABLE mart.usuarios_activos_diario AS
SELECT d.full_date AS periodo,
       t.source_name AS origen,
       COUNT(DISTINCT w.active_user_key) AS usuarios_activos,
       COUNT(*) AS sesiones
FROM fact_web_session AS w
JOIN dim_date    AS d ON d.date_key    = w.date_key
JOIN dim_traffic AS t ON t.traffic_key = w.traffic_key
GROUP BY ALL
UNION ALL
SELECT d.full_date, 'Todos',
       COUNT(DISTINCT w.active_user_key), COUNT(*)
FROM fact_web_session AS w
JOIN dim_date AS d ON d.date_key = w.date_key
GROUP BY ALL
ORDER BY periodo, origen;

-- mart.usuarios_activos_mensual: usuarios distintos por mes y origen (+ fila 'Todos')
CREATE TABLE mart.usuarios_activos_mensual AS
SELECT d.year_month AS periodo,
       t.source_name AS origen,
       COUNT(DISTINCT w.active_user_key) AS usuarios_activos,
       COUNT(*) AS sesiones
FROM fact_web_session AS w
JOIN dim_date    AS d ON d.date_key    = w.date_key
JOIN dim_traffic AS t ON t.traffic_key = w.traffic_key
GROUP BY ALL
UNION ALL
SELECT d.year_month, 'Todos',
       COUNT(DISTINCT w.active_user_key), COUNT(*)
FROM fact_web_session AS w
JOIN dim_date AS d ON d.date_key = w.date_key
GROUP BY ALL
ORDER BY periodo, origen;

-- mart.nps_diario: NPS ya calculado por día y canal (+ fila 'Todos')
CREATE TABLE mart.nps_diario AS
SELECT periodo, canal, respuestas, promotores, pasivos, detractores,
       (promotores - detractores) * 100.0 / respuestas AS nps
FROM (
    SELECT d.full_date AS periodo, ch.name AS canal,
           COUNT(*) AS respuestas,
           COUNT(*) FILTER (WHERE n.nps_category = 'PROMOTER')  AS promotores,
           COUNT(*) FILTER (WHERE n.nps_category = 'PASSIVE')   AS pasivos,
           COUNT(*) FILTER (WHERE n.nps_category = 'DETRACTOR') AS detractores
    FROM fact_nps AS n
    JOIN dim_date    AS d  ON d.date_key     = n.date_key
    JOIN dim_channel AS ch ON ch.channel_key = n.channel_key
    GROUP BY ALL
    UNION ALL
    SELECT d.full_date, 'Todos',
           COUNT(*),
           COUNT(*) FILTER (WHERE n.nps_category = 'PROMOTER'),
           COUNT(*) FILTER (WHERE n.nps_category = 'PASSIVE'),
           COUNT(*) FILTER (WHERE n.nps_category = 'DETRACTOR')
    FROM fact_nps AS n
    JOIN dim_date AS d ON d.date_key = n.date_key
    GROUP BY ALL
)
ORDER BY periodo, canal;

-- mart.nps_mensual: NPS ya calculado por mes y canal (+ fila 'Todos')
CREATE TABLE mart.nps_mensual AS
SELECT periodo, canal, respuestas, promotores, pasivos, detractores,
       (promotores - detractores) * 100.0 / respuestas AS nps
FROM (
    SELECT d.year_month AS periodo, ch.name AS canal,
           COUNT(*) AS respuestas,
           COUNT(*) FILTER (WHERE n.nps_category = 'PROMOTER')  AS promotores,
           COUNT(*) FILTER (WHERE n.nps_category = 'PASSIVE')   AS pasivos,
           COUNT(*) FILTER (WHERE n.nps_category = 'DETRACTOR') AS detractores
    FROM fact_nps AS n
    JOIN dim_date    AS d  ON d.date_key     = n.date_key
    JOIN dim_channel AS ch ON ch.channel_key = n.channel_key
    GROUP BY ALL
    UNION ALL
    SELECT d.year_month, 'Todos',
           COUNT(*),
           COUNT(*) FILTER (WHERE n.nps_category = 'PROMOTER'),
           COUNT(*) FILTER (WHERE n.nps_category = 'PASSIVE'),
           COUNT(*) FILTER (WHERE n.nps_category = 'DETRACTOR')
    FROM fact_nps AS n
    JOIN dim_date AS d ON d.date_key = n.date_key
    GROUP BY ALL
)
ORDER BY periodo, canal;

-- mart.ranking_producto_mensual: ventas por producto y mes, con su posición (ranking_mes)
-- line_total no incluye IVA ni envío (por eso no coincide con mart.ventas_*)
CREATE TABLE mart.ranking_producto_mensual AS
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
ORDER BY b.mes, r.ranking_mes, b.canal, b.provincia;

-- Verificaciones. Esperado: 382410636 | 10998 | 34770.93
SELECT SUM(ventas) AS ventas, SUM(pedidos) AS pedidos,
       ROUND(SUM(ventas) / SUM(pedidos), 2) AS ticket_promedio
FROM mart.ticket_mensual;

-- Esperado: NPS global 30.0
SELECT ROUND((SUM(promotores) - SUM(detractores)) * 100.0 / SUM(respuestas), 1) AS nps
FROM mart.nps_mensual WHERE canal <> 'Todos';