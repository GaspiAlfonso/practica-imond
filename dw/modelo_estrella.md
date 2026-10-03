# Modelo estrella

Generado por `run_sql.py` a partir de las tablas de `warehouse.duckdb`.

```mermaid
erDiagram
    dim_channel ||--o{ fact_nps : "channel_key"
    dim_channel ||--o{ fact_payment : "channel_key"
    dim_channel ||--o{ fact_sales_item : "channel_key"
    dim_channel ||--o{ fact_sales_order : "channel_key"
    dim_channel ||--o{ fact_shipment : "channel_key"
    dim_customer ||--o{ fact_nps : "customer_key"
    dim_customer ||--o{ fact_sales_item : "customer_key"
    dim_customer ||--o{ fact_sales_order : "customer_key"
    dim_customer ||--o{ fact_web_session : "customer_key"
    dim_date ||--o{ fact_nps : "date_key"
    dim_date ||--o{ fact_payment : "date_key"
    dim_date ||--o{ fact_payment : "paid_date_key"
    dim_date ||--o{ fact_sales_item : "date_key"
    dim_date ||--o{ fact_sales_order : "date_key"
    dim_date ||--o{ fact_shipment : "date_key"
    dim_date ||--o{ fact_shipment : "delivered_date_key"
    dim_date ||--o{ fact_shipment : "shipped_date_key"
    dim_date ||--o{ fact_web_session : "date_key"
    dim_order_status ||--o{ fact_sales_item : "status_key"
    dim_order_status ||--o{ fact_sales_order : "status_key"
    dim_payment_method ||--o{ fact_payment : "payment_method_key"
    dim_payment_method ||--o{ fact_sales_order : "payment_method_key"
    dim_product ||--o{ fact_sales_item : "product_key"
    dim_province ||--o{ fact_sales_item : "province_key"
    dim_province ||--o{ fact_sales_order : "province_key"
    dim_province ||--o{ fact_shipment : "province_key"
    dim_store ||--o{ fact_sales_item : "store_key"
    dim_store ||--o{ fact_sales_order : "store_key"
    dim_store ||--o{ fact_shipment : "store_key"
    dim_traffic ||--o{ fact_web_session : "traffic_key"
    dim_channel {
        INTEGER channel_key PK
        INTEGER channel_id
        VARCHAR code
        VARCHAR name
    }
    dim_customer {
        INTEGER customer_key PK
        INTEGER customer_id
        VARCHAR email
        VARCHAR first_name
        VARCHAR last_name
        VARCHAR full_name
        VARCHAR phone
        VARCHAR status
        VARCHAR status_name
        TIMESTAMP created_at
    }
    dim_date {
        INTEGER date_key PK
        DATE full_date
        SMALLINT year
        SMALLINT quarter
        SMALLINT month
        VARCHAR month_name
        VARCHAR year_month
        SMALLINT week_of_year
        SMALLINT day
        SMALLINT day_of_week
        VARCHAR day_name
        BOOLEAN is_weekend
    }
    dim_order_status {
        INTEGER status_key PK
        VARCHAR status
        VARCHAR description
        BOOLEAN is_sale
    }
    dim_payment_method {
        INTEGER payment_method_key PK
        VARCHAR method
        VARCHAR method_name
    }
    dim_product {
        INTEGER product_key PK
        INTEGER product_id
        VARCHAR sku
        VARCHAR name
        VARCHAR category
        VARCHAR family
        DECIMAL list_price
    }
    dim_province {
        INTEGER province_key PK
        INTEGER province_id
        VARCHAR name
        VARCHAR code
    }
    dim_store {
        INTEGER store_key PK
        INTEGER store_id
        VARCHAR name
        VARCHAR city
        VARCHAR province_name
    }
    dim_traffic {
        INTEGER traffic_key PK
        VARCHAR source
        VARCHAR source_name
        VARCHAR device
    }
    fact_nps {
        BIGINT nps_id PK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        SMALLINT score
        VARCHAR nps_category
        VARCHAR comment
        TIMESTAMP responded_at
    }
    fact_payment {
        BIGINT payment_id PK
        BIGINT order_id
        INTEGER date_key FK
        INTEGER paid_date_key FK
        INTEGER channel_key FK
        INTEGER payment_method_key FK
        VARCHAR status
        DECIMAL amount
        TIMESTAMP paid_at
        VARCHAR transaction_ref
    }
    fact_sales_item {
        BIGINT order_item_id PK
        BIGINT order_id
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER store_key FK
        INTEGER province_key FK
        INTEGER product_key FK
        INTEGER status_key FK
        BOOLEAN is_sale
        INTEGER quantity
        DECIMAL unit_price
        DECIMAL discount_amount
        DECIMAL line_total
    }
    fact_sales_order {
        BIGINT order_id PK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER store_key FK
        INTEGER province_key FK
        INTEGER payment_method_key FK
        INTEGER status_key FK
        TIMESTAMP order_timestamp
        BOOLEAN is_sale
        DECIMAL subtotal
        DECIMAL tax_amount
        DECIMAL shipping_fee
        DECIMAL total_amount
    }
    fact_shipment {
        BIGINT shipment_id PK
        BIGINT order_id
        INTEGER date_key FK
        INTEGER shipped_date_key FK
        INTEGER delivered_date_key FK
        INTEGER channel_key FK
        INTEGER store_key FK
        INTEGER province_key FK
        VARCHAR carrier
        VARCHAR tracking_number
        VARCHAR status
        TIMESTAMP shipped_at
        TIMESTAMP delivered_at
        DOUBLE delivery_days
    }
    fact_web_session {
        BIGINT session_id PK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER traffic_key FK
        VARCHAR active_user_key
        BOOLEAN is_logged_in
        TIMESTAMP started_at
        TIMESTAMP ended_at
        INTEGER duration_seconds
    }
```
