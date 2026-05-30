-- ============================================================
-- RetailVault Stored Procedures & Functions
-- Microsoft SQL Server 2022
-- All analytics queries moved from JPA @Query into T-SQL procs
-- ============================================================

-- ============================================================
-- 1. usp_GetKpiSummary
--    Returns total revenue, profit, units sold, order count,
--    and profit margin for a given year.
--    Uses window functions for YoY comparison.
-- ============================================================
CREATE OR ALTER PROCEDURE usp_GetKpiSummary
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;

    WITH CurrentYear AS (
        SELECT
            SUM(fs.net_revenue)   AS total_revenue,
            SUM(fs.gross_profit)  AS total_profit,
            SUM(fs.quantity)      AS total_units,
            COUNT(DISTINCT fs.order_id) AS total_orders
        FROM fact_sales fs
        INNER JOIN dim_date dd ON fs.date_key = dd.date_key
        WHERE dd.year = @Year
    ),
    PriorYear AS (
        SELECT
            SUM(fs.net_revenue) AS prior_revenue
        FROM fact_sales fs
        INNER JOIN dim_date dd ON fs.date_key = dd.date_key
        WHERE dd.year = @Year - 1
    )
    SELECT
        cy.total_revenue,
        cy.total_profit,
        cy.total_units,
        cy.total_orders,
        CASE WHEN cy.total_revenue > 0
             THEN CAST(cy.total_profit / cy.total_revenue * 100 AS DECIMAL(10,2))
             ELSE 0 END AS profit_margin_pct,
        -- YoY growth %
        CASE WHEN py.prior_revenue > 0
             THEN CAST((cy.total_revenue - py.prior_revenue) / py.prior_revenue * 100 AS DECIMAL(10,2))
             ELSE NULL END AS yoy_revenue_growth_pct
    FROM CurrentYear cy
    CROSS JOIN PriorYear py;
END
GO

-- ============================================================
-- 2. usp_GetMonthlySales
--    Monthly revenue + profit with running total (window fn).
-- ============================================================
CREATE OR ALTER PROCEDURE usp_GetMonthlySales
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;

    WITH Monthly AS (
        SELECT
            dd.month_name,
            dd.month_num,
            SUM(fs.net_revenue)  AS revenue,
            SUM(fs.gross_profit) AS profit
        FROM fact_sales fs
        INNER JOIN dim_date dd ON fs.date_key = dd.date_key
        WHERE dd.year = @Year
        GROUP BY dd.month_name, dd.month_num
    )
    SELECT
        month_name,
        month_num,
        revenue,
        profit,
        -- Running total using window function
        SUM(revenue) OVER (ORDER BY month_num
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
            AS running_revenue
    FROM Monthly
    ORDER BY month_num;
END
GO

-- ============================================================
-- 3. usp_GetTopProducts
--    Top N products by revenue with rank using DENSE_RANK().
-- ============================================================
CREATE OR ALTER PROCEDURE usp_GetTopProducts
    @Year  INT,
    @TopN  INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    WITH ProductSales AS (
        SELECT
            dp.product_name,
            dp.category_name,
            SUM(fs.net_revenue)  AS revenue,
            SUM(fs.quantity)     AS units_sold,
            SUM(fs.gross_profit) AS profit,
            DENSE_RANK() OVER (ORDER BY SUM(fs.net_revenue) DESC) AS revenue_rank
        FROM fact_sales fs
        INNER JOIN dim_product dp ON fs.product_key = dp.product_key
        INNER JOIN dim_date    dd ON fs.date_key    = dd.date_key
        WHERE dd.year = @Year
          AND dp.is_current = 1
        GROUP BY dp.product_name, dp.category_name
    )
    SELECT TOP (@TopN)
        product_name,
        category_name,
        revenue,
        units_sold,
        profit,
        revenue_rank
    FROM ProductSales
    ORDER BY revenue_rank;
END
GO

-- ============================================================
-- 4. usp_GetSalesByStore
--    Revenue per store with % share of total (window fn).
-- ============================================================
CREATE OR ALTER PROCEDURE usp_GetSalesByStore
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ds.store_name,
        SUM(fs.net_revenue)  AS revenue,
        SUM(fs.quantity)     AS units_sold,
        SUM(fs.gross_profit) AS profit,
        CAST(
            SUM(fs.net_revenue) * 100.0 /
            NULLIF(SUM(SUM(fs.net_revenue)) OVER (), 0)
        AS DECIMAL(10,2)) AS pct_of_total
    FROM fact_sales fs
    INNER JOIN dim_store ds ON fs.store_key = ds.store_key
    INNER JOIN dim_date  dd ON fs.date_key  = dd.date_key
    WHERE dd.year = @Year
      AND ds.is_current = 1
    GROUP BY ds.store_name
    ORDER BY revenue DESC;
END
GO

-- ============================================================
-- 5. usp_GetSalesByCategory
-- ============================================================
CREATE OR ALTER PROCEDURE usp_GetSalesByCategory
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        dp.category_name,
        SUM(fs.net_revenue) AS revenue,
        SUM(fs.quantity)    AS units_sold
    FROM fact_sales fs
    INNER JOIN dim_product dp ON fs.product_key = dp.product_key
    INNER JOIN dim_date    dd ON fs.date_key    = dd.date_key
    WHERE dd.year = @Year
      AND dp.is_current = 1
    GROUP BY dp.category_name
    ORDER BY revenue DESC;
END
GO

-- ============================================================
-- 6. usp_GetSalesByRegion
-- ============================================================
CREATE OR ALTER PROCEDURE usp_GetSalesByRegion
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ds.region,
        SUM(fs.net_revenue) AS revenue,
        SUM(fs.quantity)    AS units_sold
    FROM fact_sales fs
    INNER JOIN dim_store ds ON fs.store_key = ds.store_key
    INNER JOIN dim_date  dd ON fs.date_key  = dd.date_key
    WHERE dd.year = @Year
      AND ds.is_current = 1
    GROUP BY ds.region
    ORDER BY revenue DESC;
END
GO

-- ============================================================
-- 7. usp_GetLowStockAlerts
--    Products currently below reorder threshold.
--    Uses LAG() to show last movement trend.
-- ============================================================
CREATE OR ALTER PROCEDURE usp_GetLowStockAlerts
AS
BEGIN
    SET NOCOUNT ON;

    WITH LatestInventory AS (
        SELECT
            fi.product_key,
            fi.store_key,
            fi.stock_after,
            fi.reorder_level,
            fi.quantity_moved,
            fi.movement_type,
            ROW_NUMBER() OVER (
                PARTITION BY fi.product_key, fi.store_key
                ORDER BY fi.date_key DESC, fi.inventory_key DESC
            ) AS rn
        FROM fact_inventory fi
        WHERE fi.is_below_reorder = 1
    )
    SELECT
        dp.product_name,
        ds.store_name,
        li.stock_after   AS current_stock,
        li.reorder_level,
        -- Quantity difference below reorder
        li.reorder_level - li.stock_after AS units_short
    FROM LatestInventory li
    INNER JOIN dim_product dp ON li.product_key = dp.product_key
    INNER JOIN dim_store   ds ON li.store_key   = ds.store_key
    WHERE li.rn = 1
      AND dp.is_current = 1
      AND ds.is_current = 1
    ORDER BY units_short DESC;
END
GO

-- ============================================================
-- 8. usp_GetInventoryTurnover
--    Turnover = units sold / avg stock level.
--    Demonstrates advanced aggregation + division handling.
-- ============================================================
CREATE OR ALTER PROCEDURE usp_GetInventoryTurnover
AS
BEGIN
    SET NOCOUNT ON;

    WITH Sales AS (
        SELECT
            fs.product_key,
            SUM(fs.quantity) AS total_units_sold
        FROM fact_sales fs
        GROUP BY fs.product_key
    ),
    AvgStock AS (
        SELECT
            fi.product_key,
            AVG(CAST(fi.stock_after AS FLOAT)) AS avg_stock
        FROM fact_inventory fi
        GROUP BY fi.product_key
    )
    SELECT
        dp.product_name,
        dp.category_name,
        s.total_units_sold,
        CAST(
            CASE WHEN av.avg_stock > 0
                 THEN s.total_units_sold / av.avg_stock
                 ELSE 0 END
        AS DECIMAL(10,2)) AS turnover_ratio,
        CAST(av.avg_stock AS INT) AS avg_stock_level
    FROM Sales s
    INNER JOIN AvgStock    av ON s.product_key = av.product_key
    INNER JOIN dim_product dp ON s.product_key = dp.product_key
    WHERE dp.is_current = 1
    ORDER BY turnover_ratio DESC;
END
GO

-- ============================================================
-- 9. usp_GetInventoryMovementSummary
-- ============================================================
CREATE OR ALTER PROCEDURE usp_GetInventoryMovementSummary
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        fi.movement_type,
        COUNT(*)         AS event_count,
        SUM(fi.quantity_moved) AS total_quantity
    FROM fact_inventory fi
    INNER JOIN dim_date dd ON fi.date_key = dd.date_key
    WHERE dd.year = @Year
    GROUP BY fi.movement_type
    ORDER BY total_quantity DESC;
END
GO

-- ============================================================
-- 10. usp_RunEtlPipeline
--     Orchestrates the full ETL inside SQL Server as a proc.
--     Java calls this; all heavy lifting stays in the DB tier.
--     Demonstrates transaction management + error handling.
-- ============================================================
CREATE OR ALTER PROCEDURE usp_RunEtlPipeline
    @TriggeredBy NVARCHAR(50) = 'SCHEDULER'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RunId    BIGINT;
    DECLARE @ErrMsg   NVARCHAR(MAX);
    DECLARE @Rows     INT = 0;

    -- Create audit record
    INSERT INTO etl_run_log (job_name, status, triggered_by)
    VALUES ('FULL_ETL', 'RUNNING', @TriggeredBy);
    SET @RunId = SCOPE_IDENTITY();

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ---- Dim Date (rolling 3-year window) ----
        DECLARE @d DATE = DATEADD(YEAR, -2, CAST(GETDATE() AS DATE));
        DECLARE @end DATE = DATEADD(YEAR, 1, CAST(GETDATE() AS DATE));

        WHILE @d <= @end
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dim_date WHERE date_key = CAST(FORMAT(@d,'yyyyMMdd') AS INT))
            BEGIN
                INSERT INTO dim_date
                    (date_key, full_date, day_of_week, day_name, day_of_month,
                     day_of_year, week_of_year, month_num, month_name, quarter,
                     year, is_weekend, is_holiday)
                VALUES (
                    CAST(FORMAT(@d,'yyyyMMdd') AS INT),
                    @d,
                    DATEPART(WEEKDAY, @d),
                    DATENAME(WEEKDAY, @d),
                    DAY(@d),
                    DATEPART(DAYOFYEAR, @d),
                    DATEPART(WEEK, @d),
                    MONTH(@d),
                    DATENAME(MONTH, @d),
                    DATEPART(QUARTER, @d),
                    YEAR(@d),
                    CASE WHEN DATEPART(WEEKDAY,@d) IN (1,7) THEN 1 ELSE 0 END,
                    0
                );
                SET @Rows = @Rows + 1;
            END
            SET @d = DATEADD(DAY, 1, @d);
        END

        -- ---- SCD Type 2: Dim Store ----
        INSERT INTO dim_store
            (store_id, store_name, city, state, region, store_type, opened_date,
             effective_date, is_current)
        SELECT
            s.store_id, s.store_name, s.city, s.state, s.region,
            s.store_type, s.opened_date, CAST(GETDATE() AS DATE), 1
        FROM RetailVault_OLTP.dbo.stores s
        WHERE NOT EXISTS (
            SELECT 1 FROM dim_store ds
            WHERE ds.store_id = s.store_id AND ds.is_current = 1
        );
        SET @Rows = @Rows + @@ROWCOUNT;

        -- ---- SCD Type 2: Dim Product ----
        INSERT INTO dim_product
            (product_id, sku, product_name, category_name, parent_category,
             supplier_name, supplier_country, unit_price, cost_price,
             effective_date, is_current)
        SELECT
            p.product_id, p.sku, p.product_name,
            ISNULL(c.category_name, 'Unknown'),
            ISNULL(c.parent_category, 'Unknown'),
            ISNULL(sup.supplier_name, 'Unknown'),
            ISNULL(sup.country, 'Unknown'),
            p.unit_price, p.cost_price,
            CAST(GETDATE() AS DATE), 1
        FROM RetailVault_OLTP.dbo.products p
        LEFT JOIN RetailVault_OLTP.dbo.categories c ON p.category_id = c.category_id
        LEFT JOIN RetailVault_OLTP.dbo.suppliers  sup ON p.supplier_id = sup.supplier_id
        WHERE NOT EXISTS (
            SELECT 1 FROM dim_product dp
            WHERE dp.product_id = p.product_id AND dp.is_current = 1
        );
        SET @Rows = @Rows + @@ROWCOUNT;

        -- ---- Dim Supplier ----
        INSERT INTO dim_supplier (supplier_id, supplier_name, contact_name, country, is_current)
        SELECT s.supplier_id, s.supplier_name, s.contact_name, s.country, 1
        FROM RetailVault_OLTP.dbo.suppliers s
        WHERE NOT EXISTS (
            SELECT 1 FROM dim_supplier ds
            WHERE ds.supplier_id = s.supplier_id AND ds.is_current = 1
        );
        SET @Rows = @Rows + @@ROWCOUNT;

        -- ---- Dim Customer ----
        INSERT INTO dim_customer (customer_id, full_name, city, state, is_current)
        SELECT c.customer_id,
               LTRIM(ISNULL(c.first_name,'') + ' ' + ISNULL(c.last_name,'')),
               c.city, c.state, 1
        FROM RetailVault_OLTP.dbo.customers c
        WHERE NOT EXISTS (
            SELECT 1 FROM dim_customer dc
            WHERE dc.customer_id = c.customer_id AND dc.is_current = 1
        );
        SET @Rows = @Rows + @@ROWCOUNT;

        -- ---- Fact Sales (incremental: last 2 years only) ----
        INSERT INTO fact_sales
            (date_key, store_key, product_key, customer_key, order_id,
             quantity, unit_price, discount_pct,
             gross_revenue, discount_amount, net_revenue, cost_of_goods, gross_profit)
        SELECT
            CAST(FORMAT(CAST(o.order_date AS DATE),'yyyyMMdd') AS INT),
            ds.store_key,
            dp.product_key,
            dc.customer_key,
            o.order_id,
            oi.quantity,
            oi.unit_price,
            ISNULL(oi.discount, 0),
            oi.quantity * oi.unit_price,
            oi.quantity * oi.unit_price * ISNULL(oi.discount,0) / 100.0,
            oi.line_total,
            oi.quantity * ISNULL(p.cost_price, 0),
            oi.line_total - oi.quantity * ISNULL(p.cost_price, 0)
        FROM RetailVault_OLTP.dbo.order_items oi
        INNER JOIN RetailVault_OLTP.dbo.orders   o  ON oi.order_id   = o.order_id
        INNER JOIN RetailVault_OLTP.dbo.products p  ON oi.product_id = p.product_id
        INNER JOIN dim_store   ds ON o.store_id       = ds.store_id   AND ds.is_current = 1
        INNER JOIN dim_product dp ON oi.product_id    = dp.product_id AND dp.is_current = 1
        LEFT  JOIN dim_customer dc ON o.customer_id   = dc.customer_id AND dc.is_current = 1
        WHERE o.order_date >= DATEADD(YEAR, -2, GETDATE())
          AND NOT EXISTS (
              SELECT 1 FROM fact_sales fs2
              WHERE fs2.order_id = o.order_id
                AND fs2.product_key = dp.product_key
          );
        SET @Rows = @Rows + @@ROWCOUNT;

        -- ---- Fact Inventory ----
        INSERT INTO fact_inventory
            (date_key, store_key, product_key, supplier_key,
             movement_type, quantity_moved, stock_before, stock_after,
             reorder_level, is_below_reorder)
        SELECT
            CAST(FORMAT(CAST(il.movement_date AS DATE),'yyyyMMdd') AS INT),
            ds.store_key,
            dp.product_key,
            dsup.supplier_key,
            il.movement_type,
            il.quantity,
            il.stock_before,
            il.stock_after,
            15,  -- configurable reorder threshold
            CASE WHEN il.stock_after < 15 THEN 1 ELSE 0 END
        FROM RetailVault_OLTP.dbo.inventory_log il
        INNER JOIN RetailVault_OLTP.dbo.products p ON il.product_id = p.product_id
        INNER JOIN dim_store   ds   ON il.store_id      = ds.store_id   AND ds.is_current = 1
        INNER JOIN dim_product dp   ON il.product_id    = dp.product_id AND dp.is_current = 1
        LEFT  JOIN dim_supplier dsup ON p.supplier_id   = dsup.supplier_id AND dsup.is_current = 1
        WHERE il.movement_date >= DATEADD(YEAR, -2, GETDATE())
          AND NOT EXISTS (
              SELECT 1 FROM fact_inventory fi2
              WHERE fi2.date_key = CAST(FORMAT(CAST(il.movement_date AS DATE),'yyyyMMdd') AS INT)
                AND fi2.store_key    = ds.store_key
                AND fi2.product_key  = dp.product_key
                AND fi2.quantity_moved = il.quantity
          );
        SET @Rows = @Rows + @@ROWCOUNT;

        COMMIT TRANSACTION;

        UPDATE etl_run_log
        SET status = 'SUCCESS', completed_at = SYSDATETIME(), rows_loaded = @Rows
        WHERE run_id = @RunId;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @ErrMsg = ERROR_MESSAGE();
        UPDATE etl_run_log
        SET status = 'FAILED', completed_at = SYSDATETIME(),
            error_message = @ErrMsg
        WHERE run_id = @RunId;
        THROW;
    END CATCH;

    SELECT @RunId AS run_id, @Rows AS rows_loaded;
END
GO

-- ============================================================
-- SCALAR FUNCTION: fn_DateKey
-- Converts a DATETIME2 to the YYYYMMDD integer date key.
-- ============================================================
CREATE OR ALTER FUNCTION fn_DateKey(@dt DATETIME2)
RETURNS INT
AS
BEGIN
    RETURN CAST(FORMAT(CAST(@dt AS DATE), 'yyyyMMdd') AS INT);
END
GO

-- ============================================================
-- TABLE-VALUED FUNCTION: fn_GetSalesDateRange
-- Returns fact_sales rows between two dates — used by reports
-- and demonstrates inline TVF pattern.
-- ============================================================
CREATE OR ALTER FUNCTION fn_GetSalesDateRange
(
    @StartDate DATE,
    @EndDate   DATE
)
RETURNS TABLE
AS
RETURN (
    SELECT
        fs.sales_key,
        dd.full_date,
        ds.store_name,
        dp.product_name,
        dp.category_name,
        fs.quantity,
        fs.net_revenue,
        fs.gross_profit
    FROM fact_sales fs
    INNER JOIN dim_date    dd ON fs.date_key    = dd.date_key
    INNER JOIN dim_store   ds ON fs.store_key   = ds.store_key
    INNER JOIN dim_product dp ON fs.product_key = dp.product_key
    WHERE dd.full_date BETWEEN @StartDate AND @EndDate
      AND ds.is_current = 1
      AND dp.is_current = 1
);
GO
