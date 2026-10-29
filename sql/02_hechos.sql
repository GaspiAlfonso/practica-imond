-- =====================================================================
-- 02_hechos.sql — Tablas de HECHOS del modelo estrella
-- =====================================================================
-- Este archivo se ejecuta después de 01_dimensiones.sql porque los hechos
-- apuntan a las dimensiones con FOREIGN KEY (REFERENCES).
--
-- Para cada tabla de hechos:
--   1. Definí el GRANO: ¿qué representa UNA fila?
--      (ej.: un producto dentro de un pedido, una sesión web, una respuesta NPS)
--   2. CREATE TABLE con:
--        - PRIMARY KEY
--        - una FOREIGN KEY por cada dimensión:  product_key INTEGER REFERENCES dim_product (product_key)
--        - las métricas (cantidades, importes, puntajes...)
--   3. INSERT INTO ... SELECT uniendo las tablas de origen (raw.) con las dimensiones
--      para obtener las claves.
--
-- Patrón para obtener la clave de una dimensión:
--
--   SELECT i.order_item_id, p.product_key, i.quantity, i.line_total
--   FROM raw.sales_order_item AS i
--   JOIN dim_product AS p ON p.product_id = i.product_id
--
-- Si una FOREIGN KEY apunta a una clave que no existe en la dimensión,
-- DuckDB rechaza la carga y run_sql.py te muestra el error.
-- =====================================================================


-- TU TURNO: creá acá las tablas de hechos.
-- =====================================================================
-- TU TURNO RESUELTO: tablas de hechos
-- =====================================================================
-- Convención: si un dato puede venir vacío en origen, se usa la clave -1
-- (fila "Desconocido") con COALESCE(clave, -1).
-- order_id / order_item_id / payment_id... son dimensiones degeneradas:
-- identificadores del sistema de origen que se guardan en el hecho.
-- =====================================================================


-- ---------------------------------------------------------------------
-- fact_sales_order
-- GRANO: un pedido.   Sirve para Ventas, Ticket Promedio y Ventas por provincia.
-- La provincia sale de la dirección de envío (en tienda, la de la tienda).
-- ---------------------------------------------------------------------
CREATE TABLE fact_sales_order (
    order_id           BIGINT  PRIMARY KEY,
    date_key           INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key       INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key        INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    store_key          INTEGER NOT NULL REFERENCES dim_store (store_key),
    province_key       INTEGER NOT NULL REFERENCES dim_province (province_key),
    payment_method_key INTEGER NOT NULL REFERENCES dim_payment_method (payment_method_key),
    status_key         INTEGER NOT NULL REFERENCES dim_order_status (status_key),
    order_timestamp    TIMESTAMP NOT NULL,
    is_sale            BOOLEAN NOT NULL,
    subtotal           DECIMAL(12, 2) NOT NULL,   -- sin IVA
    tax_amount         DECIMAL(12, 2) NOT NULL,   -- IVA 21 %
    shipping_fee       DECIMAL(12, 2) NOT NULL,
    total_amount       DECIMAL(12, 2) NOT NULL    -- subtotal + IVA + envío
);

INSERT INTO fact_sales_order
SELECT
    o.order_id,
    CAST(strftime(o.order_date, '%Y%m%d') AS INTEGER),
    COALESCE(c.customer_key, -1),
    ch.channel_key,
    COALESCE(s.store_key, -1),
    pr.province_key,
    pm.payment_method_key,
    st.status_key,
    o.order_date,
    st.is_sale,
    o.subtotal,
    o.tax_amount,
    o.shipping_fee,
    o.total_amount
FROM raw.sales_order AS o
JOIN raw.payment             AS p  ON p.order_id = o.order_id
JOIN raw.address             AS a  ON a.address_id = o.shipping_address_id
JOIN dim_channel             AS ch ON ch.channel_id = o.channel_id
JOIN dim_province            AS pr ON pr.province_id = a.province_id
JOIN dim_payment_method      AS pm ON pm.method = p.method
JOIN dim_order_status        AS st ON st.status = o.status
LEFT JOIN dim_customer       AS c  ON c.customer_id = o.customer_id
LEFT JOIN dim_store          AS s  ON s.store_id = o.store_id;


-- ---------------------------------------------------------------------
-- fact_sales_item
-- GRANO: un producto dentro de un pedido.   Sirve para el Ranking por producto.
-- ---------------------------------------------------------------------
CREATE TABLE fact_sales_item (
    order_item_id   BIGINT  PRIMARY KEY,
    order_id        BIGINT  NOT NULL,
    date_key        INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key    INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key     INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    store_key       INTEGER NOT NULL REFERENCES dim_store (store_key),
    province_key    INTEGER NOT NULL REFERENCES dim_province (province_key),
    product_key     INTEGER NOT NULL REFERENCES dim_product (product_key),
    status_key      INTEGER NOT NULL REFERENCES dim_order_status (status_key),
    is_sale         BOOLEAN NOT NULL,
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    unit_price      DECIMAL(12, 2) NOT NULL,
    discount_amount DECIMAL(12, 2) NOT NULL,
    line_total      DECIMAL(12, 2) NOT NULL    -- cantidad * precio - descuento (sin IVA ni envío)
);

INSERT INTO fact_sales_item
SELECT
    i.order_item_id,
    i.order_id,
    o.date_key,
    o.customer_key,
    o.channel_key,
    o.store_key,
    o.province_key,
    p.product_key,
    o.status_key,
    o.is_sale,
    i.quantity,
    i.unit_price,
    i.discount_amount,
    i.line_total
FROM raw.sales_order_item AS i
JOIN fact_sales_order AS o ON o.order_id = i.order_id
JOIN dim_product      AS p ON p.product_id = i.product_id;


-- ---------------------------------------------------------------------
-- fact_payment
-- GRANO: un pago (uno por pedido).   Sirve para conciliar ventas vs. cobros.
-- ---------------------------------------------------------------------
CREATE TABLE fact_payment (
    payment_id         BIGINT  PRIMARY KEY,
    order_id           BIGINT  NOT NULL,
    date_key           INTEGER NOT NULL REFERENCES dim_date (date_key),       -- fecha del pedido
    paid_date_key      INTEGER REFERENCES dim_date (date_key),                -- NULL si no se cobró
    channel_key        INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    payment_method_key INTEGER NOT NULL REFERENCES dim_payment_method (payment_method_key),
    status             VARCHAR NOT NULL,       -- PENDING / PAID / FAILED / REFUNDED
    amount             DECIMAL(12, 2) NOT NULL,
    paid_at            TIMESTAMP,
    transaction_ref    VARCHAR
);

INSERT INTO fact_payment
SELECT
    p.payment_id,
    p.order_id,
    o.date_key,
    CAST(strftime(p.paid_at, '%Y%m%d') AS INTEGER),
    o.channel_key,
    pm.payment_method_key,
    p.status,
    p.amount,
    p.paid_at,
    p.transaction_ref
FROM raw.payment AS p
JOIN fact_sales_order   AS o  ON o.order_id = p.order_id
JOIN dim_payment_method AS pm ON pm.method = p.method;


-- ---------------------------------------------------------------------
-- fact_shipment
-- GRANO: un envío.   Sirve para logística (tiempos de entrega).
-- ---------------------------------------------------------------------
CREATE TABLE fact_shipment (
    shipment_id        BIGINT  PRIMARY KEY,
    order_id           BIGINT  NOT NULL,
    date_key           INTEGER NOT NULL REFERENCES dim_date (date_key),       -- fecha del pedido
    shipped_date_key   INTEGER REFERENCES dim_date (date_key),
    delivered_date_key INTEGER REFERENCES dim_date (date_key),
    channel_key        INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    store_key          INTEGER NOT NULL REFERENCES dim_store (store_key),
    province_key       INTEGER NOT NULL REFERENCES dim_province (province_key),
    carrier            VARCHAR,
    tracking_number    VARCHAR,
    status             VARCHAR NOT NULL,       -- READY / SHIPPED / DELIVERED / CANCELLED
    shipped_at         TIMESTAMP,
    delivered_at       TIMESTAMP,
    delivery_days      DOUBLE                  -- días entre envío y entrega (NULL si no se entregó)
);

INSERT INTO fact_shipment
SELECT
    s.shipment_id,
    s.order_id,
    o.date_key,
    CAST(strftime(s.shipped_at, '%Y%m%d') AS INTEGER),
    CAST(strftime(s.delivered_at, '%Y%m%d') AS INTEGER),
    o.channel_key,
    o.store_key,
    o.province_key,
    s.carrier,
    s.tracking_number,
    s.status,
    s.shipped_at,
    s.delivered_at,
    CASE WHEN s.delivered_at IS NOT NULL AND s.shipped_at IS NOT NULL
         THEN date_diff('second', s.shipped_at, s.delivered_at) / 86400.0 END
FROM raw.shipment AS s
JOIN fact_sales_order AS o ON o.order_id = s.order_id;


-- ---------------------------------------------------------------------
-- fact_web_session
-- GRANO: una sesión web.   Sirve para Usuarios Activos.
-- active_user_key identifica al "usuario": el cliente si inició sesión
-- ('C123') o la propia sesión si es anónimo ('S456').
-- ---------------------------------------------------------------------
CREATE TABLE fact_web_session (
    session_id       BIGINT  PRIMARY KEY,
    date_key         INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key     INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    traffic_key      INTEGER NOT NULL REFERENCES dim_traffic (traffic_key),
    active_user_key  VARCHAR NOT NULL,
    is_logged_in     BOOLEAN NOT NULL,
    started_at       TIMESTAMP NOT NULL,
    ended_at         TIMESTAMP,
    duration_seconds INTEGER
);

INSERT INTO fact_web_session
SELECT
    w.session_id,
    CAST(strftime(w.started_at, '%Y%m%d') AS INTEGER),
    COALESCE(c.customer_key, -1),
    t.traffic_key,
    CASE WHEN w.customer_id IS NULL THEN 'S' || w.session_id ELSE 'C' || w.customer_id END,
    w.customer_id IS NOT NULL,
    w.started_at,
    w.ended_at,
    CASE WHEN w.ended_at IS NOT NULL THEN date_diff('second', w.started_at, w.ended_at) END
FROM raw.web_session AS w
JOIN dim_traffic AS t ON t.source = COALESCE(w.source, 'unknown')
                     AND t.device = COALESCE(w.device, 'unknown')
LEFT JOIN dim_customer AS c ON c.customer_id = w.customer_id;


-- ---------------------------------------------------------------------
-- fact_nps
-- GRANO: una respuesta de la encuesta NPS.
-- Categoría: 9-10 promotor, 7-8 pasivo, 0-6 detractor.
-- ---------------------------------------------------------------------
CREATE TABLE fact_nps (
    nps_id        BIGINT  PRIMARY KEY,
    date_key      INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key  INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key   INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    score         SMALLINT NOT NULL CHECK (score BETWEEN 0 AND 10),
    nps_category  VARCHAR NOT NULL,      -- PROMOTER / PASSIVE / DETRACTOR
    comment       VARCHAR,
    responded_at  TIMESTAMP NOT NULL
);

INSERT INTO fact_nps
SELECT
    n.nps_id,
    CAST(strftime(n.responded_at, '%Y%m%d') AS INTEGER),
    COALESCE(c.customer_key, -1),
    ch.channel_key,
    n.score,
    CASE WHEN n.score >= 9 THEN 'PROMOTER' WHEN n.score >= 7 THEN 'PASSIVE' ELSE 'DETRACTOR' END,
    n.comment,
    n.responded_at
FROM raw.nps_response AS n
JOIN dim_channel AS ch ON ch.channel_id = n.channel_id
LEFT JOIN dim_customer AS c ON c.customer_id = n.customer_id;

