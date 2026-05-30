-- ============================================================
-- RetailVault OLTP Source Schema
-- Microsoft SQL Server 2022 Compatible
-- ============================================================
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Create database if running standalone (comment out if using existing DB)
-- CREATE DATABASE RetailVault_OLTP;
-- GO
-- USE RetailVault_OLTP;
-- GO

-- ============================================================
-- TABLES
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'stores')
CREATE TABLE stores (
    store_id        INT IDENTITY(1,1) PRIMARY KEY,
    store_name      NVARCHAR(100) NOT NULL,
    city            NVARCHAR(100),
    state           NVARCHAR(50),
    region          NVARCHAR(50),
    store_type      NVARCHAR(50),
    opened_date     DATE,
    created_at      DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'suppliers')
CREATE TABLE suppliers (
    supplier_id     INT IDENTITY(1,1) PRIMARY KEY,
    supplier_name   NVARCHAR(100) NOT NULL,
    contact_name    NVARCHAR(100),
    email           NVARCHAR(100),
    phone           NVARCHAR(20),
    country         NVARCHAR(50),
    created_at      DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'categories')
CREATE TABLE categories (
    category_id     INT IDENTITY(1,1) PRIMARY KEY,
    category_name   NVARCHAR(100) NOT NULL,
    parent_category NVARCHAR(100)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'products')
CREATE TABLE products (
    product_id      INT IDENTITY(1,1) PRIMARY KEY,
    sku             NVARCHAR(50) NOT NULL UNIQUE,
    product_name    NVARCHAR(200) NOT NULL,
    category_id     INT,
    supplier_id     INT,
    unit_price      DECIMAL(10,2),
    cost_price      DECIMAL(10,2),
    created_at      DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT fk_products_category FOREIGN KEY (category_id) REFERENCES categories(category_id),
    CONSTRAINT fk_products_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'customers')
CREATE TABLE customers (
    customer_id     INT IDENTITY(1,1) PRIMARY KEY,
    first_name      NVARCHAR(100),
    last_name       NVARCHAR(100),
    email           NVARCHAR(100),
    city            NVARCHAR(100),
    state           NVARCHAR(50),
    created_at      DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'orders')
CREATE TABLE orders (
    order_id        INT IDENTITY(1,1) PRIMARY KEY,
    customer_id     INT,
    store_id        INT NOT NULL,
    order_date      DATETIME2 NOT NULL,
    status          NVARCHAR(30) DEFAULT 'COMPLETED',
    total_amount    DECIMAL(12,2),
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_orders_store    FOREIGN KEY (store_id)    REFERENCES stores(store_id)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'order_items')
CREATE TABLE order_items (
    item_id         INT IDENTITY(1,1) PRIMARY KEY,
    order_id        INT NOT NULL,
    product_id      INT NOT NULL,
    quantity        INT NOT NULL,
    unit_price      DECIMAL(10,2) NOT NULL,
    discount        DECIMAL(5,2) DEFAULT 0.00,
    -- Computed column (persisted for index support)
    line_total      AS (CAST(quantity * unit_price * (1 - discount / 100.0) AS DECIMAL(12,2))) PERSISTED,
    CONSTRAINT fk_orderitems_order   FOREIGN KEY (order_id)   REFERENCES orders(order_id),
    CONSTRAINT fk_orderitems_product FOREIGN KEY (product_id) REFERENCES products(product_id)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'inventory_log')
CREATE TABLE inventory_log (
    log_id          INT IDENTITY(1,1) PRIMARY KEY,
    product_id      INT NOT NULL,
    store_id        INT NOT NULL,
    movement_type   NVARCHAR(20) NOT NULL
                    CHECK (movement_type IN ('RESTOCK','SALE','RETURN','ADJUSTMENT','TRANSFER')),
    quantity        INT NOT NULL,
    stock_before    INT,
    stock_after     INT,
    reference_id    INT,
    movement_date   DATETIME2 NOT NULL,
    notes           NVARCHAR(255),
    CONSTRAINT fk_invlog_product FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT fk_invlog_store   FOREIGN KEY (store_id)   REFERENCES stores(store_id)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'inventory_snapshot')
CREATE TABLE inventory_snapshot (
    snapshot_id     INT IDENTITY(1,1) PRIMARY KEY,
    product_id      INT NOT NULL,
    store_id        INT NOT NULL,
    current_stock   INT DEFAULT 0,
    reorder_level   INT DEFAULT 10,
    last_updated    DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT uq_product_store UNIQUE (product_id, store_id),
    CONSTRAINT fk_snap_product FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT fk_snap_store   FOREIGN KEY (store_id)   REFERENCES stores(store_id)
);
GO

-- ============================================================
-- INDEXES (covering indexes for common query patterns)
-- ============================================================

-- Orders by date range (most common analytics filter)
CREATE NONCLUSTERED INDEX idx_orders_date
    ON orders(order_date)
    INCLUDE (store_id, customer_id, total_amount, status);
GO

-- Order items with product lookup
CREATE NONCLUSTERED INDEX idx_orderitems_product
    ON order_items(product_id)
    INCLUDE (order_id, quantity, unit_price, discount, line_total);
GO

-- Inventory log by date (ETL incremental extract)
CREATE NONCLUSTERED INDEX idx_invlog_date
    ON inventory_log(movement_date)
    INCLUDE (product_id, store_id, movement_type, quantity, stock_before, stock_after);
GO

-- Inventory log by product+store (turnover queries)
CREATE NONCLUSTERED INDEX idx_invlog_product_store
    ON inventory_log(product_id, store_id)
    INCLUDE (movement_type, quantity, movement_date);
GO

-- Low stock detection
CREATE NONCLUSTERED INDEX idx_snap_stock
    ON inventory_snapshot(current_stock)
    INCLUDE (product_id, store_id, reorder_level);
GO
