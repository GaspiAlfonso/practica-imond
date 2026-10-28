-- =====================================================================
-- 05_data_marts_dashboard.sql — Data marts para el dashboard
-- Cada combinación de filtros trae su fila, con 'Todos' como total.
-- Los indicadores (ticket, NPS, usuarios, ranking) ya vienen calculados:
-- Power BI solo muestra la fila elegida, sin medidas propias.
-- =====================================================================

-- Valores de los filtros (con la opción 'Todos')
CREATE TABLE dim_filtro_mes AS
SELECT 'Todos' AS mes
UNION ALL
SELECT DISTINCT year_month FROM dim_date
ORDER BY mes;

CREATE TABLE dim_filtro_canal AS
SELECT 'Todos' AS canal
UNION ALL
SELECT name FROM dim_channel
ORDER BY canal;

CREATE TABLE dim_filtro_provincia AS
SELECT 'Todos' AS provincia
UNION ALL
SELECT name FROM dim_province
ORDER BY provincia;

-- dm_resumen_ventas: ventas, pedidos, ticket, IVA y envío por mes x canal x provincia
CREATE TABLE dm_resumen_ventas AS
SELECT
    COALESCE(d.year_month, 'Todos')                AS mes,
    COALESCE(ch.name, 'Todos')                     AS canal,
    COALESCE(p.name, 'Todos')                      AS provincia,
    COUNT(*)                                       AS pedidos,
    CAST(SUM(o.total_amount) AS DOUBLE)            AS ventas,
    CAST(SUM(o.subtotal) AS DOUBLE)                AS ventas_sin_iva,
    CAST(SUM(o.tax_amount) AS DOUBLE)              AS iva,
    CAST(SUM(o.shipping_fee) AS DOUBLE)            AS envio,
    CAST(SUM(o.total_amount) AS DOUBLE) / COUNT(*) AS ticket_promedio
FROM fact_sales_order AS o
JOIN dim_date     AS d  ON d.date_key     = o.date_key
JOIN dim_channel  AS ch ON ch.channel_key = o.channel_key
JOIN dim_province AS p  ON p.province_key = o.province_key
WHERE o.is_sale
GROUP BY CUBE (d.year_month, ch.name, p.name)
ORDER BY mes, canal, provincia;

-- dm_resumen_nps: NPS ya calculado por mes x canal
CREATE TABLE dm_resumen_nps AS
SELECT mes, canal, respuestas, promotores, pasivos, detractores,
       (promotores - detractores) * 100.0 / respuestas AS nps
FROM (
    SELECT COALESCE(d.year_month, 'Todos') AS mes,
           COALESCE(ch.name, 'Todos')      AS canal,
           COUNT(*) AS respuestas,
           COUNT(*) FILTER (WHERE n.nps_category = 'PROMOTER')  AS promotores,
           COUNT(*) FILTER (WHERE n.nps_category = 'PASSIVE')   AS pasivos,
           COUNT(*) FILTER (WHERE n.nps_category = 'DETRACTOR') AS detractores
    FROM fact_nps AS n
    JOIN dim_date    AS d  ON d.date_key     = n.date_key
    JOIN dim_channel AS ch ON ch.channel_key = n.channel_key
    GROUP BY CUBE (d.year_month, ch.name)
)
ORDER BY mes, canal;

-- dm_resumen_usuarios: usuarios distintos por mes x origen de tráfico
CREATE TABLE dm_resumen_usuarios AS
SELECT COALESCE(d.year_month, 'Todos')   AS mes,
       COALESCE(t.source_name, 'Todos')  AS origen,
       COUNT(DISTINCT w.active_user_key) AS usuarios_activos,
       COUNT(*)                          AS sesiones
FROM fact_web_session AS w
JOIN dim_date    AS d ON d.date_key    = w.date_key
JOIN dim_traffic AS t ON t.traffic_key = w.traffic_key
GROUP BY CUBE (d.year_month, t.source_name)
ORDER BY mes, origen;

-- dm_resumen_ranking_producto: ventas por producto con su posición (ranking)
-- en cada combinación de mes x canal x provincia. line_total no incluye IVA ni envío.
CREATE TABLE dm_resumen_ranking_producto AS
WITH base AS (
    SELECT COALESCE(d.year_month, 'Todos') AS mes,
           COALESCE(ch.name, 'Todos')      AS canal,
           COALESCE(pr.name, 'Todos')      AS provincia,
           p.name                          AS producto,
           p.category                      AS categoria,
           SUM(i.quantity)                 AS unidades,
           CAST(SUM(i.line_total) AS DOUBLE) AS ventas_items
    FROM fact_sales_item AS i
    JOIN dim_date     AS d  ON d.date_key      = i.date_key
    JOIN dim_channel  AS ch ON ch.channel_key  = i.channel_key
    JOIN dim_province AS pr ON pr.province_key = i.province_key
    JOIN dim_product  AS p  ON p.product_key   = i.product_key
    WHERE i.is_sale
    GROUP BY CUBE (d.year_month, ch.name, pr.name), p.name, p.category
)
SELECT *,
       RANK() OVER (PARTITION BY mes, canal, provincia ORDER BY ventas_items DESC) AS ranking
FROM base
ORDER BY mes, canal, provincia, ranking;

-- Verificaciones
-- V1. Esperado: 382410636 | 10998 | 34770.93 | 309891600 | 65077236 | 7441800
SELECT ventas, pedidos, ROUND(ticket_promedio, 2) AS ticket, ventas_sin_iva, iva, envio
FROM dm_resumen_ventas
WHERE mes = 'Todos' AND canal = 'Todos' AND provincia = 'Todos';

-- V2. Esperado: 3083 | 30.0
SELECT respuestas, ROUND(nps, 1) AS nps
FROM dm_resumen_nps WHERE mes = 'Todos' AND canal = 'Todos';

-- V3. Esperado: 73828 | 100363
SELECT usuarios_activos, sesiones
FROM dm_resumen_usuarios WHERE mes = 'Todos' AND origen = 'Todos';

-- V4. Esperado: Sport B 11047 u. y ranking 1; Classic A 12498 u. y ranking 2
SELECT producto, unidades, ventas_items, ranking
FROM dm_resumen_ranking_producto
WHERE mes = 'Todos' AND canal = 'Todos' AND provincia = 'Todos'
ORDER BY ranking;

-- V5. Esperado: 0 (el resumen coincide con dm_ticket_mensual en el detalle)
SELECT COUNT(*) AS diferencias FROM (
    (SELECT mes, canal, provincia, pedidos, ventas FROM dm_resumen_ventas
     WHERE mes <> 'Todos' AND canal <> 'Todos' AND provincia <> 'Todos'
     EXCEPT
     SELECT mes, canal, provincia, pedidos, ventas FROM dm_ticket_mensual)
    UNION ALL
    (SELECT mes, canal, provincia, pedidos, ventas FROM dm_ticket_mensual
     EXCEPT
     SELECT mes, canal, provincia, pedidos, ventas FROM dm_resumen_ventas
     WHERE mes <> 'Todos' AND canal <> 'Todos' AND provincia <> 'Todos')
);

