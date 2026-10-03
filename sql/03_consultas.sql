-- =====================================================================
-- 03_consultas.sql — Consultas para revisar el modelo y calcular KPIs
-- =====================================================================
-- Cada SELECT de este archivo se muestra en la terminal al ejecutar
-- run_sql.py. Usalo para:
--   * comprobar que las tablas se cargaron bien (cantidad de filas, nulos...)
--   * escribir las consultas clave de los KPIs que pide la consigna
--     (ventas, usuarios activos, ticket promedio, NPS, ventas por provincia,
--     ranking mensual por producto) usando las tablas del modelo estrella.
-- =====================================================================


-- Ejemplo: revisar la dimensión producto
SELECT product_key, name, category, family, list_price
FROM dim_product
ORDER BY product_key;


-- =====================================================================
-- TU TURNO RESUELTO: validaciones y consultas clave
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. VALIDACIONES DEL MODELO
-- ---------------------------------------------------------------------

-- A1. Filas: cada hecho debe tener las mismas filas que su tabla de origen
SELECT 'sales_order'      AS tabla, (SELECT COUNT(*) FROM raw.sales_order)      AS origen, (SELECT COUNT(*) FROM fact_sales_order) AS dw
UNION ALL SELECT 'sales_order_item', (SELECT COUNT(*) FROM raw.sales_order_item), (SELECT COUNT(*) FROM fact_sales_item)
UNION ALL SELECT 'payment',          (SELECT COUNT(*) FROM raw.payment),          (SELECT COUNT(*) FROM fact_payment)
UNION ALL SELECT 'shipment',         (SELECT COUNT(*) FROM raw.shipment),         (SELECT COUNT(*) FROM fact_shipment)
UNION ALL SELECT 'web_session',      (SELECT COUNT(*) FROM raw.web_session),      (SELECT COUNT(*) FROM fact_web_session)
UNION ALL SELECT 'nps_response',     (SELECT COUNT(*) FROM raw.nps_response),     (SELECT COUNT(*) FROM fact_nps);

-- A2. Los importes del DW coinciden con el origen (la diferencia debe ser 0)
SELECT
    (SELECT SUM(total_amount) FROM raw.sales_order) - (SELECT SUM(total_amount) FROM fact_sales_order) AS dif_total_pedidos,
    (SELECT SUM(line_total) FROM raw.sales_order_item) - (SELECT SUM(line_total) FROM fact_sales_item) AS dif_total_items;

-- A3. Cuentas que cierran: subtotal = suma de ítems y total = subtotal + IVA + envío (ambos deben dar 0)
SELECT
    (SELECT COUNT(*) FROM fact_sales_order AS o
     JOIN (SELECT order_id, SUM(line_total) AS s FROM fact_sales_item GROUP BY order_id) AS i USING (order_id)
     WHERE ABS(o.subtotal - i.s) > 0.01) AS pedidos_subtotal_no_cierra,
    (SELECT COUNT(*) FROM fact_sales_order
     WHERE ABS(total_amount - (subtotal + tax_amount + shipping_fee)) > 0.01) AS pedidos_total_no_cierra;

-- A4. Pedidos por estado y si cuentan como venta
SELECT s.status, s.is_sale, COUNT(*) AS pedidos, SUM(o.total_amount) AS monto
FROM fact_sales_order AS o
JOIN dim_order_status AS s USING (status_key)
GROUP BY s.status, s.is_sale
ORDER BY s.status;

-- A5. Claves "Desconocido" (-1): pedidos online sin tienda y NPS / sesiones anónimas
SELECT 'pedidos sin tienda (online)' AS caso, COUNT(*) AS filas FROM fact_sales_order WHERE store_key = -1
UNION ALL SELECT 'sesiones web anónimas', COUNT(*) FROM fact_web_session WHERE customer_key = -1
UNION ALL SELECT 'NPS anónimos',          COUNT(*) FROM fact_nps WHERE customer_key = -1;


-- ---------------------------------------------------------------------
-- B. KPIs DEL TABLERO
-- ---------------------------------------------------------------------

-- B1. Ventas totales ($) y pedidos — solo PAID y FULFILLED
SELECT SUM(total_amount) AS ventas_totales, COUNT(*) AS pedidos
FROM fact_sales_order
WHERE is_sale;

-- B2. Ventas por mes y canal (serie temporal)
SELECT d.year_month AS mes, ch.name AS canal, SUM(o.total_amount) AS ventas
FROM fact_sales_order AS o
JOIN dim_date    AS d  USING (date_key)
JOIN dim_channel AS ch USING (channel_key)
WHERE o.is_sale
GROUP BY d.year_month, ch.name
ORDER BY mes, canal;

-- B3. Ticket promedio = ventas / pedidos, por canal
SELECT ch.name AS canal, SUM(o.total_amount) / COUNT(*) AS ticket_promedio
FROM fact_sales_order AS o
JOIN dim_channel AS ch USING (channel_key)
WHERE o.is_sale
GROUP BY ch.name
ORDER BY canal;

-- B4. Usuarios activos por mes (cliente logueado, o sesión si es anónimo)
SELECT d.year_month AS mes,
       COUNT(DISTINCT w.active_user_key) AS usuarios_activos,
       COUNT(DISTINCT w.customer_key) FILTER (WHERE w.is_logged_in) AS clientes_logueados,
       COUNT(*) AS sesiones
FROM fact_web_session AS w
JOIN dim_date AS d USING (date_key)
GROUP BY d.year_month
ORDER BY mes;

-- B5. NPS por mes = (%promotores - %detractores) * 100
SELECT d.year_month AS mes,
       COUNT(*) AS respuestas,
       ROUND((COUNT(*) FILTER (WHERE n.nps_category = 'PROMOTER')
            - COUNT(*) FILTER (WHERE n.nps_category = 'DETRACTOR')) * 100.0 / COUNT(*), 1) AS nps
FROM fact_nps AS n
JOIN dim_date AS d USING (date_key)
GROUP BY d.year_month
ORDER BY mes;

-- B6. NPS por canal
SELECT ch.name AS canal,
       COUNT(*) AS respuestas,
       ROUND((COUNT(*) FILTER (WHERE n.nps_category = 'PROMOTER')
            - COUNT(*) FILTER (WHERE n.nps_category = 'DETRACTOR')) * 100.0 / COUNT(*), 1) AS nps
FROM fact_nps AS n
JOIN dim_channel AS ch USING (channel_key)
GROUP BY ch.name
ORDER BY canal;

-- B7. Ventas por provincia (provincia de la dirección de envío)
SELECT p.name AS provincia, SUM(o.total_amount) AS ventas, COUNT(*) AS pedidos
FROM fact_sales_order AS o
JOIN dim_province AS p USING (province_key)
WHERE o.is_sale
GROUP BY p.name
ORDER BY ventas DESC;

-- B8. Ranking mensual por producto (line_total: sin IVA ni envío)
SELECT d.year_month AS mes,
       p.name AS producto,
       SUM(i.line_total) AS ventas_items,
       RANK() OVER (PARTITION BY d.year_month ORDER BY SUM(i.line_total) DESC) AS ranking
FROM fact_sales_item AS i
JOIN dim_date    AS d USING (date_key)
JOIN dim_product AS p USING (product_key)
WHERE i.is_sale
GROUP BY d.year_month, p.name
ORDER BY mes, ranking;


-- ---------------------------------------------------------------------
-- C. CONSULTAS EXTRA (hallazgos para el informe)
-- ---------------------------------------------------------------------

-- C1. Tasa de conversión web: sesiones del mes vs pedidos ONLINE que son venta
SELECT s.mes, s.sesiones, v.pedidos_online,
       ROUND(v.pedidos_online * 100.0 / s.sesiones, 2) AS conversion_pct
FROM (SELECT d.year_month AS mes, COUNT(*) AS sesiones
      FROM fact_web_session AS w JOIN dim_date AS d USING (date_key) GROUP BY 1) AS s
JOIN (SELECT d.year_month AS mes, COUNT(*) AS pedidos_online
      FROM fact_sales_order AS o
      JOIN dim_date AS d USING (date_key)
      JOIN dim_channel AS ch USING (channel_key)
      WHERE o.is_sale AND ch.code = 'ONLINE' GROUP BY 1) AS v USING (mes)
ORDER BY s.mes;

-- C2. Tasa de cancelación y devolución por canal
SELECT ch.name AS canal,
       ROUND(COUNT(*) FILTER (WHERE s.status = 'CANCELLED') * 100.0 / COUNT(*), 1) AS cancelados_pct,
       ROUND(COUNT(*) FILTER (WHERE s.status = 'REFUNDED')  * 100.0 / COUNT(*), 1) AS devueltos_pct
FROM fact_sales_order AS o
JOIN dim_channel      AS ch USING (channel_key)
JOIN dim_order_status AS s  USING (status_key)
GROUP BY ch.name
ORDER BY canal;

-- C3. Ventas por origen de tráfico no se puede cruzar (la sesión no tiene pedido): ver README, supuestos.
-- C4. Tiempo promedio de entrega (días) por provincia, solo envíos entregados
SELECT p.name AS provincia, ROUND(AVG(s.delivery_days), 1) AS dias_promedio, COUNT(*) AS envios
FROM fact_shipment AS s
JOIN dim_province AS p USING (province_key)
WHERE s.status = 'DELIVERED'
GROUP BY p.name
ORDER BY dias_promedio;

-- C5. Ventas por método de pago
SELECT m.method_name AS metodo, COUNT(*) AS pedidos, SUM(o.total_amount) AS ventas
FROM fact_sales_order AS o
JOIN dim_payment_method AS m USING (payment_method_key)
WHERE o.is_sale
GROUP BY m.method_name
ORDER BY ventas DESC;


