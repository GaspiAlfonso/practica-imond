-- =====================================================================
-- 01_dimensiones.sql — Tablas de DIMENSIONES del modelo estrella
-- =====================================================================
-- Para cada dimensión:
--   1. CREATE TABLE con sus columnas, tipos y PRIMARY KEY.
--   2. INSERT INTO ... SELECT para cargarla desde las tablas de origen.
--
-- Las tablas de origen (los CSV de raw/) están en el esquema raw:
--     FROM raw.product
-- Para ver qué columnas y tipos tiene una:  DESCRIBE raw.product;
-- Para explorarlas antes de escribir nada:  python run_sql.py --explorar
-- =====================================================================


-- ---------------------------------------------------------------------
-- EJEMPLO RESUELTO: dimensión producto
-- ---------------------------------------------------------------------
-- En raw/ la categoría está en otra tabla y tiene jerarquía
-- (Bottles -> Classic / Sport). En la dimensión la "aplanamos":
-- cada producto queda en una sola fila con su categoría y su familia.
--
-- product_key es la clave SUBROGADA: un número propio del data warehouse.
-- product_id es la clave NATURAL: el ID que viene del sistema de origen.
-- Las tablas de hechos usan product_key; product_id sirve para encontrarla.

CREATE TABLE dim_product (
    product_key INTEGER PRIMARY KEY,
    product_id  INTEGER NOT NULL,
    sku         VARCHAR NOT NULL,
    name        VARCHAR NOT NULL,
    category    VARCHAR,             -- Classic / Sport
    family      VARCHAR,             -- Bottles
    list_price  DECIMAL(12, 2)
);

INSERT INTO dim_product
SELECT
    ROW_NUMBER() OVER (ORDER BY p.product_id) AS product_key,
    p.product_id,
    p.sku,
    p.name,
    c.name AS category,
    f.name AS family,
    p.list_price
FROM raw.product AS p
LEFT JOIN raw.product_category AS c ON c.category_id = p.category_id   -- categoría
LEFT JOIN raw.product_category AS f ON f.category_id = c.parent_id;    -- familia (categoría padre)


-- ---------------------------------------------------------------------
-- TU TURNO: el resto de las dimensiones
-- ---------------------------------------------------------------------
-- Pensá qué preguntas tiene que responder el dashboard (por fecha, canal,
-- provincia, producto, cliente, tienda...) y creá una dimensión para cada una.
--
-- Tips:
--   * Generar todas las fechas entre dos días:
--       SELECT CAST(range AS DATE) AS fecha
--       FROM range(DATE '2024-01-01', DATE '2025-10-01', INTERVAL 1 DAY);
--   * Partes de una fecha: year(fecha), month(fecha), monthname(fecha), dayname(fecha)
--   * Clave numérica para una fecha (ej. 20240131):
--       CAST(strftime(fecha, '%Y%m%d') AS INTEGER)
--   * Si algo puede venir vacío (ej. NPS anónimos, sin cliente), podés agregar
--     una fila "Desconocido" con clave -1 y usar COALESCE(clave, -1) en los hechos.

-- ---------------------------------------------------------------------
-- dim_date: una fila por día entre el 01/01/2024 y el 30/09/2025
-- date_key es una clave "inteligente" AAAAMMDD (ej. 20240131)
-- ---------------------------------------------------------------------

CREATE TABLE dim_date (
    date_key    INTEGER PRIMARY KEY,
    full_date DATE NOT NULL,
    year SMALLINT NOT NULL,
    quarter SMALLINT NOT NULL,
    month SMALLINT NOT NULL,
    month_name VARCHAR NOT NULL,
    year_month VARCHAR NOT NULL,
    week_of_year SMALLINT NOT NULL,
    day SMALLINT NOT NULL,
    day_of_week SMALLINT NOT NULL,
    day_name VARCHAR NOT NULL,
    is_weekend BOOLEAN NOT NULL
);

INSERT INTO dim_date
SELECT
    CAST(strftime(d, '%Y%m%d') AS INTEGER),
    d,
    year(d),
    quarter(d),
    month(d),
    monthname(d),
    strftime(d, '%Y-%m'),
    weekofyear(d),
    day(d),
    isodow(d),
    dayname(d),
    isodow(d) IN (6,7)
FROM (SELECT CAST(range AS DATE) AS d
      FROM range(DATE '2024-01-01', DATE '2025-10-01', INTERVAL 1 DAY));

CREATE TABLE dim_channel (
    channel_key  INTEGER PRIMARY KEY,
    channel_id   INTEGER NOT NULL,
    code         VARCHAR NOT NULL,
    name         VARCHAR NOT NULL
);


-- ---------------------------------------------------------------------
-- dim_channel: ONLINE / OFFLINE
-- ---------------------------------------------------------------------

INSERT INTO dim_channel
SELECT ROW_NUMBER() OVER (ORDER BY channel_id), channel_id, code, name
FROM raw.channel;

-- ---------------------------------------------------------------------
-- dim_province
-- ---------------------------------------------------------------------

CREATE TABLE dim_province (
    province_key INTEGER PRIMARY KEY,
    province_id INTEGER NOT NULL,
    name VARCHAR NOT NULL,
    code VARCHAR
); 

INSERT INTO dim_province
SELECT ROW_NUMBER() OVER (ORDER BY province_id), province_id, name, code
FROM raw.province;

-- ---------------------------------------------------------------------
-- dim_customer: incluye la fila -1 "Desconocido" para NPS y sesiones anónimas
-- ---------------------------------------------------------------------

CREATE TABLE dim_customer (
    customer_key INTEGER PRIMARY KEY,
    customer_id INTEGER,                --- NULL en la fila Desconocido
    email VARCHAR,
    first_name VARCHAR,
    last_name VARCHAR,
    full_name VARCHAR NOT NULL,
    phone VARCHAR,
    status VARCHAR NOT NULL,             --- A Activo/ I dado de bajo 
    status_name VARCHAR NOT NULL,
    created_at TIMESTAMP
);

INSERT INTO dim_customer
VALUES(-1, NULL, NULL, NULL, NULL, 'Desconocido', NULL, 'N/A', 'Desconocido / anónimo', NULL);

INSERT INTO dim_customer
SELECT
    ROW_NUMBER() OVER (ORDER BY customer_id),
    customer_id,
    email,
    first_name,
    last_name,
    first_name || ' ' || last_name AS full_name,
    phone,
    status,
    CASE status WHEN 'A' THEN 'Activo' WHEN 'I' THEN 'Dado de baja' ELSE 'Desconocido' END,
    created_at
FROM raw.customer;

-- ---------------------------------------------------------------------
-- dim_store: incluye la fila -1 para los pedidos ONLINE (sin tienda)
-- ---------------------------------------------------------------------

CREATE TABLE dim_store (
    store_key     INTEGER PRIMARY KEY,
    store_id      INTEGER,
    name          VARCHAR NOT NULL,
    city          VARCHAR,
    province_name VARCHAR
);

INSERT INTO dim_store VALUES (-1, NULL, 'Online (sin tienda)', NULL, NULL);

INSERT INTO dim_store
SELECT
    ROW_NUMBER() OVER (ORDER BY s.store_id),
    s.store_id,
    s.name,
    a.city,
    p.name
FROM raw.store AS s
LEFT JOIN raw.address  AS a ON a.address_id  = s.address_id
LEFT JOIN raw.province AS p ON p.province_id = a.province_id;

-- --------------------------------------------------------------------
-- dim_payment_method: método de pago
-- -----------------------------------------------------------------------

CREATE TABLE dim_payment_method (
    payment_method_key INTEGER PRIMARY KEY,
    method             VARCHAR NOT NULL,
    method_name        VARCHAR NOT NULL
);

INSERT INTO dim_payment_method
SELECT
    ROW_NUMBER() OVER (ORDER BY method),
    method,
    CASE method
        WHEN 'CARD'     THEN 'Tarjeta'
        WHEN 'CASH'     THEN 'Efectivo'
        WHEN 'TRANSFER' THEN 'Transferencia'
        WHEN 'GATEWAY'  THEN 'Pasarela / Mercado Pago'
        ELSE method
    END
FROM (SELECT DISTINCT method FROM raw.payment);

-- ---------------------------------------------------------------------
-- dim_order_status: estado del pedido y si cuenta como venta
-- ---------------------------------------------------------------------
CREATE TABLE dim_order_status (
    status_key INTEGER PRIMARY KEY,
    status VARCHAR NOT NULL,
    description VARCHAR NOT NULL,
    is_sale BOOLEAN NOT NULL        -- TRUE solo para PAID y FULFILLED
);

INSERT INTO dim_order_status VALUES
    (1, 'CREATED',   'Pedido creado, todavía sin pagar',         FALSE),
    (2, 'PAID',      'Pagado, todavía no entregado',             TRUE),
    (3, 'FULFILLED', 'Entregado o comprado en tienda',           TRUE),
    (4, 'CANCELLED', 'Cancelado',                                FALSE),
    (5, 'REFUNDED',  'Entregado y luego devuelto el dinero',     FALSE);

-- ---------------------------------------------------------------------
-- dim_traffic: origen + dispositivo de las sesiones web
-- ---------------------------------------------------------------------
CREATE TABLE dim_traffic (
    traffic_key INTEGER PRIMARY KEY,
    source      VARCHAR NOT NULL,
    source_name VARCHAR NOT NULL,
    device      VARCHAR NOT NULL
);

INSERT INTO dim_traffic
SELECT
    ROW_NUMBER() OVER (ORDER BY source, device),
    source,
    CASE source
        WHEN 'ads'      THEN 'Publicidad en redes'
        WHEN 'direct'   THEN 'Directo / newsletter'
        WHEN 'referral' THEN 'Referido'
        WHEN 'organic'  THEN 'Buscadores (orgánico)'
        ELSE source
    END,
    device
FROM (SELECT DISTINCT COALESCE(source, 'unknown') AS source,
                      COALESCE(device, 'unknown') AS device
      FROM raw.web_session);