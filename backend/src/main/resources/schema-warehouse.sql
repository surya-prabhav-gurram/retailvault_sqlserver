-- ============================================================
-- RetailVault Data Warehouse Schema (Star Schema)
-- Microsoft SQL Server 2022 Compatible
-- ============================================================

-- ============================================================
-- DIMENSION TABLES
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'dim_date')
CREATE TABLE dim_date (
    date_key        INT PRIMARY KEY,
    full_date       DATE NOT NULL,
    day_of_week     TINYINT,
    day_name        NVARCHAR(10),
    day_of_month    TINYINT,
    day_of_year     SMALLINT,
    week_of_year    TINYINT,
    month_num       TINYINT,
    month_name      NVARCHAR(10),
    quarter         TINYINT,
    year            SMALLINT,
    is_weekend      BIT,
    is_holiday      BIT DEFAULT 0
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'dim_store')
CREATE TABLE dim_store (
    store_key       INT IDENTITY(1,1) PRIMARY KEY,
    store_id        INT NOT NULL,
    store_name      NVARCHAR(100),
    city            NVARCHAR(100),
    state           NVARCHAR(50),
    region          NVARCHAR(50),
    store_type      NVARCHAR(50),
    opened_date     DATE,
    effective_date  DATE,
    expiry_date     DATE,
    is_current      BIT DEFAULT 1
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'dim_product')
CREATE TABLE dim_product (
    product_key     INT IDENTITY(1,1) PRIMARY KEY,
    product_id      INT NOT NULL,
    sku             NVARCHAR(50),
    product_name    NVARCHAR(200),
    category_name   NVARCHAR(100),
    parent_category NVARCHAR(100),
    supplier_name   NVARCHAR(100),
    supplier_country NVARCHAR(50),
    unit_price      DECIMAL(10,2),
    cost_price      DECIMAL(10,2),
    effective_date  DATE,
    expiry_date     DATE,
    is_current      BIT DEFAULT 1
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'dim_supplier')
CREATE TABLE dim_supplier (
    supplier_key    INT IDENTITY(1,1) PRIMARY KEY,
    supplier_id     INT NOT NULL,
    supplier_name   NVARCHAR(100),
    contact_name    NVARCHAR(100),
    country         NVARCHAR(50),
    is_current      BIT DEFAULT 1
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'dim_customer')
CREATE TABLE dim_customer (
    customer_key    INT IDENTITY(1,1) PRIMARY KEY,
    customer_id     INT NOT NULL,
    full_name       NVARCHAR(200),
    city            NVARCHAR(100),
    state           NVARCHAR(50),
    is_current      BIT DEFAULT 1
);
GO

-- ============================================================
-- FACT TABLES
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'fact_sales')
CREATE TABLE fact_sales (
    sales_key       BIGINT IDENTITY(1,1) PRIMARY KEY,
    date_key        INT NOT NULL,
    store_key       INT NOT NULL,
    product_key     INT NOT NULL,
    customer_key    INT,
    order_id        INT NOT NULL,
    quantity        INT NOT NULL,
    unit_price      DECIMAL(10,2),
    discount_pct    DECIMAL(5,2),
    gross_revenue   DECIMAL(12,2),
    discount_amount DECIMAL(12,2),
    net_revenue     DECIMAL(12,2),
    cost_of_goods   DECIMAL(12,2),
    gross_profit    DECIMAL(12,2),
    CONSTRAINT fk_fs_date    FOREIGN KEY (date_key)    REFERENCES dim_date(date_key),
    CONSTRAINT fk_fs_store   FOREIGN KEY (store_key)   REFERENCES dim_store(store_key),
    CONSTRAINT fk_fs_product FOREIGN KEY (product_key) REFERENCES dim_product(product_key),
    CONSTRAINT fk_fs_customer FOREIGN KEY (customer_key) REFERENCES dim_customer(customer_key)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'fact_inventory')
CREATE TABLE fact_inventory (
    inventory_key   BIGINT IDENTITY(1,1) PRIMARY KEY,
    date_key        INT NOT NULL,
    store_key       INT NOT NULL,
    product_key     INT NOT NULL,
    supplier_key    INT,
    movement_type   NVARCHAR(20),
    quantity_moved  INT,
    stock_before    INT,
    stock_after     INT,
    reorder_level   INT,
    is_below_reorder BIT,
    CONSTRAINT fk_fi_date    FOREIGN KEY (date_key)    REFERENCES dim_date(date_key),
    CONSTRAINT fk_fi_store   FOREIGN KEY (store_key)   REFERENCES dim_store(store_key),
    CONSTRAINT fk_fi_product FOREIGN KEY (product_key) REFERENCES dim_product(product_key)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'etl_run_log')
CREATE TABLE etl_run_log (
    run_id          BIGINT IDENTITY(1,1) PRIMARY KEY,
    job_name        NVARCHAR(100),
    status          NVARCHAR(20) DEFAULT 'RUNNING'
                    CHECK (status IN ('RUNNING','SUCCESS','FAILED')),
    started_at      DATETIME2 DEFAULT SYSDATETIME(),
    completed_at    DATETIME2 NULL,
    rows_extracted  INT DEFAULT 0,
    rows_loaded     INT DEFAULT 0,
    error_message   NVARCHAR(MAX),
    triggered_by    NVARCHAR(50) DEFAULT 'SCHEDULER'
);
GO

-- ============================================================
-- WAREHOUSE INDEXES
-- Columnstore index on fact_sales for OLAP scan performance
-- ============================================================


-- Standard covering index for date-range slices (used by stored procs)
CREATE NONCLUSTERED INDEX idx_fs_date_store
    ON fact_sales(date_key, store_key)
    INCLUDE (product_key, net_revenue, gross_profit, quantity);
GO

CREATE NONCLUSTERED INDEX idx_fs_product
    ON fact_sales(product_key)
    INCLUDE (date_key, quantity, net_revenue, gross_profit);
GO

CREATE NONCLUSTERED INDEX idx_fi_date_store
    ON fact_inventory(date_key, store_key)
    INCLUDE (product_key, movement_type, quantity_moved, stock_after, is_below_reorder);
GO
