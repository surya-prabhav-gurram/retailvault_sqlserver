# RetailVault — SQL Server Edition

A full-stack retail data warehousing and analytics platform built on **Microsoft SQL Server 2022**, Spring Boot, and React. This version migrates the original MySQL implementation to the Microsoft stack, adding stored procedures, T-SQL advanced features, columnstore indexing, and a stored-procedure-driven ETL pipeline.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        React Frontend                        │
│         KPI Cards · Charts · Low-Stock Alerts · ETL Log     │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTP / REST
┌──────────────────────▼──────────────────────────────────────┐
│                   Spring Boot Backend                        │
│   AnalyticsController → AnalyticsService → JDBC CallableStatement │
│   EtlController       → EtlPipelineService → JDBC CallableStatement │
└──────────┬────────────────────────────────────┬─────────────┘
           │                                    │
┌──────────▼──────────┐            ┌────────────▼────────────┐
│  RetailVault_OLTP   │            │  RetailVault_Warehouse   │
│  (SQL Server 2022)  │            │  (SQL Server 2022)       │
│                     │            │                          │
│  stores             │  ETL Proc  │  dim_date                │
│  products      ─────┼────────►  │  dim_store  (SCD Type 2) │
│  customers          │  usp_Run  │  dim_product (SCD Type 2)│
│  orders             │  EtlPipeline  dim_customer            │
│  order_items        │            │  dim_supplier            │
│  inventory_log      │            │  fact_sales  ← NCCI      │
│  inventory_snapshot │            │  fact_inventory          │
│                     │            │  etl_run_log             │
└─────────────────────┘            └──────────────────────────┘
```

---

## SQL Server Features Used

### Stored Procedures (all in `stored-procedures.sql`)
| Procedure | Purpose |
|---|---|
| `usp_RunEtlPipeline` | Full ETL with T-SQL transaction management, SCD Type 2 loads, incremental extraction |
| `usp_GetKpiSummary` | Revenue, profit, units, orders + YoY growth using CTEs |
| `usp_GetMonthlySales` | Monthly trends with running total using `SUM() OVER()` window function |
| `usp_GetTopProducts` | Top N products ranked with `DENSE_RANK()` |
| `usp_GetSalesByStore` | Per-store revenue with `% of total` using `SUM() OVER()` |
| `usp_GetLowStockAlerts` | Latest below-reorder inventory using `ROW_NUMBER()` partitioning |
| `usp_GetInventoryTurnover` | Turnover ratio = units sold / avg stock level |
| `usp_GetSalesByCategory` | Revenue grouped by product category |
| `usp_GetSalesByRegion` | Revenue grouped by store region |
| `usp_GetInventoryMovementSummary` | Movement type breakdown by year |

### T-SQL Functions
| Function | Type | Purpose |
|---|---|---|
| `fn_DateKey` | Scalar | Converts `DATETIME2` → `INT` date key (YYYYMMDD) |
| `fn_GetSalesDateRange` | Inline TVF | Returns fact_sales rows between two dates — used by reports |

### Advanced T-SQL Features
- **Window functions**: `SUM() OVER()`, `ROW_NUMBER() OVER()`, `DENSE_RANK() OVER()`
- **CTEs**: Multi-step KPI calculations, SCD Type 2 logic
- **Computed persisted columns**: `order_items.line_total AS (quantity * unit_price * (1 - discount/100.0)) PERSISTED`
- **`TRY/CATCH` with `ROLLBACK`**: Full transaction safety in `usp_RunEtlPipeline`
- **`SCOPE_IDENTITY()`**: Safe identity retrieval after ETL audit inserts
- **`ISNULL()`, `NULLIF()`**: Null-safe division and default value handling
- **`DATEADD`, `DATEPART`, `DATENAME`, `FORMAT`**: Date manipulation throughout ETL

### Indexing Strategy
- **Nonclustered Columnstore Index** (`ncci_fact_sales`) on `fact_sales` — dramatically speeds up full-scan OLAP aggregations (SQL Server 2022 feature)
- **Covering nonclustered indexes** on both fact tables with `INCLUDE` columns to eliminate key lookups
- **Filtered/composite indexes** on OLTP tables for ETL extraction patterns
- All indexes documented with the query pattern they serve

---

## Project Structure

```
retailvault/
├── backend/
│   ├── src/main/resources/
│   │   ├── schema-oltp.sql          # SQL Server OLTP schema
│   │   ├── schema-warehouse.sql     # Star schema + columnstore index
│   │   ├── stored-procedures.sql    # All T-SQL procs + functions
│   │   ├── seed-data.sql            # Sample data
│   │   └── application.properties  # SQL Server JDBC config
│   └── src/main/java/com/retailvault/
│       ├── config/DataSourceConfig.java      # Dual datasource (OLTP + DW)
│       ├── etl/EtlPipelineService.java       # Thin JDBC wrapper → usp_RunEtlPipeline
│       ├── service/AnalyticsService.java     # JDBC CallableStatement → analytics procs
│       ├── controller/                       # REST endpoints (unchanged)
│       ├── entity/                           # JPA entities (unchanged)
│       └── dto/                              # Response DTOs (unchanged)
├── frontend/                                 # React dashboard (unchanged)
└── docker-compose.yml                        # SQL Server 2022 Developer Edition
```

---

## Quick Start

### Prerequisites
- Docker Desktop
- Java 21, Maven 3.9+
- Node.js 18+ (for frontend dev)

### 1. Start SQL Server + Initialize Databases
```bash
docker-compose up sqlserver db-init
```
This starts SQL Server 2022 Developer Edition (free), creates both databases, runs all schemas, creates stored procedures, and seeds data.

### 2. Run the Backend
```bash
cd backend
mvn spring-boot:run
```

### 3. Run the Frontend
```bash
cd frontend
npm install && npm start
```

### 4. Trigger ETL
```bash
curl -X POST http://localhost:8080/api/etl/run
```

Or use the ETL tab in the React dashboard.

---

## Connecting with SSMS / Azure Data Studio

Server: `localhost,1433`  
Authentication: SQL Server Authentication  
Login: `sa`  
Password: `YourStrong!Passw0rd`

To inspect execution plans:
```sql
USE RetailVault_Warehouse;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

EXEC usp_GetKpiSummary @Year = 2025;
```

---

## Key Design Decisions

**Why stored procedures for analytics?**  
All aggregation logic lives in T-SQL procs. This means the DBA team can tune execution plans, add indexes, or rewrite a query without touching Java. It also means SQL Server can cache compiled plans — on a large warehouse, this makes a measurable difference.

**Why a thin Java service layer?**  
`AnalyticsService` and `EtlPipelineService` are pure JDBC wrappers. They handle DTO mapping and error handling but contain zero business logic. This mirrors how enterprise database teams actually work.

**Why Columnstore on fact_sales?**  
Full-scan aggregations (SUM revenue by month, region, category) are the dominant query pattern on a warehouse fact table. A nonclustered columnstore index compresses the data column-by-column and allows batch-mode execution — typically 10-100x faster than row-store for these patterns.

**Why SCD Type 2?**  
Dimension tables track history. If a product's price changes, old sales rows still point to the historical price record (`is_current = 0`), preserving analytical accuracy.
