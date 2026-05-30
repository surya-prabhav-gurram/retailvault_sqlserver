package com.retailvault.service;

import com.retailvault.dto.*;
import com.retailvault.entity.warehouse.EtlRunLog;
import com.retailvault.repository.oltp.OrderItemRepository;
import com.retailvault.repository.warehouse.EtlRunLogRepository;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

import javax.sql.DataSource;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.*;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

/**
 * AnalyticsService — SQL Server edition.
 *
 * All analytics queries now delegate to T-SQL stored procedures
 * (usp_GetKpiSummary, usp_GetMonthlySales, etc.).
 *
 * This pattern mirrors how Hobby Lobby's DB team works:
 *   - Business logic + query tuning lives in the DB tier
 *   - Java layer handles HTTP mapping, DTO conversion, and error handling
 *   - DBAs can update execution plans / indexes without touching Java
 */
@Service
public class AnalyticsService {

    private final DataSource warehouseDataSource;
    private final EtlRunLogRepository etlRunLogRepository;
    private final OrderItemRepository orderItemRepository;

    @org.springframework.beans.factory.annotation.Autowired
    public AnalyticsService(
            @Qualifier("warehouseDataSource") DataSource warehouseDataSource,
            EtlRunLogRepository etlRunLogRepository,
            OrderItemRepository orderItemRepository) {
        this.warehouseDataSource = warehouseDataSource;
        this.etlRunLogRepository = etlRunLogRepository;
        this.orderItemRepository = orderItemRepository;
    }

    // ============================================================
    // KPI Summary — calls usp_GetKpiSummary
    // ============================================================
    public KpiSummaryDto getKpiSummary(int year) {
        String sql = "{call usp_GetKpiSummary(?)}";
        try (Connection conn = warehouseDataSource.getConnection();
             CallableStatement cs = conn.prepareCall(sql)) {

            cs.setInt(1, year);
            try (ResultSet rs = cs.executeQuery()) {
                if (rs.next()) {
                    BigDecimal revenue = toBigDecimal(rs.getObject("total_revenue"));
                    BigDecimal profit  = toBigDecimal(rs.getObject("total_profit"));
                    long units         = toLong(rs.getObject("total_units"));
                    long orders        = toLong(rs.getObject("total_orders"));
                    BigDecimal margin  = toBigDecimal(rs.getObject("profit_margin_pct"));
                    return new KpiSummaryDto(revenue, profit, units, orders, margin);
                }
            }
        } catch (SQLException e) {
            throw new RuntimeException("usp_GetKpiSummary failed: " + e.getMessage(), e);
        }
        return new KpiSummaryDto(BigDecimal.ZERO, BigDecimal.ZERO, 0L, 0L, BigDecimal.ZERO);
    }

    // ============================================================
    // Monthly Sales — calls usp_GetMonthlySales
    // ============================================================
    public List<MonthlySalesDto> getMonthlySales(int year) {
        List<MonthlySalesDto> result = new ArrayList<>();
        try (Connection conn = warehouseDataSource.getConnection();
             CallableStatement cs = conn.prepareCall("{call usp_GetMonthlySales(?)}")) {

            cs.setInt(1, year);
            try (ResultSet rs = cs.executeQuery()) {
                while (rs.next()) {
                    result.add(new MonthlySalesDto(
                            rs.getString("month_name"),
                            rs.getInt("month_num"),
                            toBigDecimal(rs.getObject("revenue")),
                            toBigDecimal(rs.getObject("profit"))
                    ));
                }
            }
        } catch (SQLException e) {
            throw new RuntimeException("usp_GetMonthlySales failed: " + e.getMessage(), e);
        }
        return result;
    }

    // ============================================================
    // Top Products — calls usp_GetTopProducts
    // ============================================================
    public List<TopProductDto> getTopProducts(int year, int topN) {
        List<TopProductDto> result = new ArrayList<>();
        try (Connection conn = warehouseDataSource.getConnection();
             CallableStatement cs = conn.prepareCall("{call usp_GetTopProducts(?,?)}")) {

            cs.setInt(1, year);
            cs.setInt(2, topN);
            try (ResultSet rs = cs.executeQuery()) {
                while (rs.next()) {
                    result.add(new TopProductDto(
                            rs.getString("product_name"),
                            rs.getString("category_name"),
                            toBigDecimal(rs.getObject("revenue")),
                            toLong(rs.getObject("units_sold")),
                            toBigDecimal(rs.getObject("profit"))
                    ));
                }
            }
        } catch (SQLException e) {
            throw new RuntimeException("usp_GetTopProducts failed: " + e.getMessage(), e);
        }
        return result;
    }

    // ============================================================
    // Sales By Store — calls usp_GetSalesByStore
    // ============================================================
    public List<SalesByStoreDto> getSalesByStore(int year) {
        List<SalesByStoreDto> result = new ArrayList<>();
        try (Connection conn = warehouseDataSource.getConnection();
             CallableStatement cs = conn.prepareCall("{call usp_GetSalesByStore(?)}")) {

            cs.setInt(1, year);
            try (ResultSet rs = cs.executeQuery()) {
                while (rs.next()) {
                    result.add(new SalesByStoreDto(
                            rs.getString("store_name"),
                            toBigDecimal(rs.getObject("revenue")),
                            toLong(rs.getObject("units_sold")),
                            toBigDecimal(rs.getObject("profit"))
                    ));
                }
            }
        } catch (SQLException e) {
            throw new RuntimeException("usp_GetSalesByStore failed: " + e.getMessage(), e);
        }
        return result;
    }

    // ============================================================
    // Sales By Category — calls usp_GetSalesByCategory
    // ============================================================
    public List<SalesByCategoryDto> getSalesByCategory(int year) {
        List<SalesByCategoryDto> result = new ArrayList<>();
        try (Connection conn = warehouseDataSource.getConnection();
             CallableStatement cs = conn.prepareCall("{call usp_GetSalesByCategory(?)}")) {

            cs.setInt(1, year);
            try (ResultSet rs = cs.executeQuery()) {
                while (rs.next()) {
                    result.add(new SalesByCategoryDto(
                            rs.getString("category_name"),
                            toBigDecimal(rs.getObject("revenue")),
                            toLong(rs.getObject("units_sold"))
                    ));
                }
            }
        } catch (SQLException e) {
            throw new RuntimeException("usp_GetSalesByCategory failed: " + e.getMessage(), e);
        }
        return result;
    }

    // ============================================================
    // Sales By Region — calls usp_GetSalesByRegion
    // ============================================================
    public List<RegionSalesDto> getSalesByRegion(int year) {
        List<RegionSalesDto> result = new ArrayList<>();
        try (Connection conn = warehouseDataSource.getConnection();
             CallableStatement cs = conn.prepareCall("{call usp_GetSalesByRegion(?)}")) {

            cs.setInt(1, year);
            try (ResultSet rs = cs.executeQuery()) {
                while (rs.next()) {
                    result.add(new RegionSalesDto(
                            rs.getString("region"),
                            toBigDecimal(rs.getObject("revenue")),
                            toLong(rs.getObject("units_sold"))
                    ));
                }
            }
        } catch (SQLException e) {
            throw new RuntimeException("usp_GetSalesByRegion failed: " + e.getMessage(), e);
        }
        return result;
    }

    // ============================================================
    // Low Stock Alerts — calls usp_GetLowStockAlerts
    // ============================================================
    public List<LowStockAlertDto> getLowStockAlerts() {
        List<LowStockAlertDto> result = new ArrayList<>();
        try (Connection conn = warehouseDataSource.getConnection();
             CallableStatement cs = conn.prepareCall("{call usp_GetLowStockAlerts}")) {

            try (ResultSet rs = cs.executeQuery()) {
                while (rs.next()) {
                    result.add(new LowStockAlertDto(
                            rs.getString("product_name"),
                            rs.getString("store_name"),
                            rs.getInt("current_stock"),
                            rs.getInt("reorder_level")
                    ));
                }
            }
        } catch (SQLException e) {
            throw new RuntimeException("usp_GetLowStockAlerts failed: " + e.getMessage(), e);
        }
        return result;
    }

    // ============================================================
    // Inventory Turnover — calls usp_GetInventoryTurnover
    // ============================================================
    public List<InventoryTurnoverDto> getInventoryTurnover() {
        List<InventoryTurnoverDto> result = new ArrayList<>();
        try (Connection conn = warehouseDataSource.getConnection();
             CallableStatement cs = conn.prepareCall("{call usp_GetInventoryTurnover}")) {

            try (ResultSet rs = cs.executeQuery()) {
                while (rs.next()) {
                    result.add(new InventoryTurnoverDto(
                            rs.getString("product_name"),
                            rs.getString("category_name"),
                            toLong(rs.getObject("total_units_sold")),
                            rs.getDouble("avg_stock_level"),
                            rs.getInt("avg_stock_level"),
                            rs.getInt("current_stock")
                    ));
                }
            }
        } catch (SQLException e) {
            throw new RuntimeException("usp_GetInventoryTurnover failed: " + e.getMessage(), e);
        }
        return result;
    }

    // ============================================================
    // Inventory Movement Summary — calls usp_GetInventoryMovementSummary
    // ============================================================
    public List<MovementSummaryDto> getInventoryMovementSummary(int year) {
        List<MovementSummaryDto> result = new ArrayList<>();
        try (Connection conn = warehouseDataSource.getConnection();
             CallableStatement cs = conn.prepareCall("{call usp_GetInventoryMovementSummary(?)}")) {

            cs.setInt(1, year);
            try (ResultSet rs = cs.executeQuery()) {
                while (rs.next()) {
                    result.add(new MovementSummaryDto(
                            rs.getString("movement_type"),
                            toLong(rs.getObject("event_count")),
                            toLong(rs.getObject("total_quantity"))
                    ));
                }
            }
        } catch (SQLException e) {
            throw new RuntimeException("usp_GetInventoryMovementSummary failed: " + e.getMessage(), e);
        }
        return result;
    }

    // ============================================================
    // ETL Run History — via JPA (no proc needed)
    // ============================================================
    public List<EtlRunLogDto> getEtlHistory() {
        return etlRunLogRepository.findTop20ByOrderByStartedAtDesc()
                .stream().map(this::toEtlDto).collect(Collectors.toList());
    }

    public List<RecentOrderDto> getRecentOrders() {
        return orderItemRepository.findRecentOrders().stream().map(r -> {
            RecentOrderDto dto = new RecentOrderDto();
            dto.setOrderId(r[0] != null ? ((Number) r[0]).intValue() : null);
            dto.setStoreName(r[1] != null ? r[1].toString() : "");
            dto.setCustomerName(r[2] != null ? r[2].toString() : "Guest");
            dto.setTotalAmount(r[3] != null ? new BigDecimal(r[3].toString()) : BigDecimal.ZERO);
            dto.setOrderDate(r[4] != null ? ((java.sql.Timestamp) r[4]).toLocalDateTime() : null);
            dto.setStatus(r[5] != null ? r[5].toString() : "");
            return dto;
        }).collect(Collectors.toList());
    }

    // ============================================================
    // Helpers
    // ============================================================
    private EtlRunLogDto toEtlDto(EtlRunLog log) {
        Long duration = null;
        if (log.getStartedAt() != null && log.getCompletedAt() != null) {
            duration = Duration.between(log.getStartedAt(), log.getCompletedAt()).getSeconds();
        }
        return new EtlRunLogDto(
                log.getRunId(), log.getJobName(), log.getStatus(),
                log.getStartedAt(), log.getCompletedAt(),
                log.getRowsExtracted(), log.getRowsLoaded(),
                log.getErrorMessage(), log.getTriggeredBy(), duration
        );
    }

    private BigDecimal toBigDecimal(Object val) {
        if (val == null) return BigDecimal.ZERO;
        if (val instanceof BigDecimal bd) return bd;
        if (val instanceof Double d) return BigDecimal.valueOf(d);
        if (val instanceof Long l) return BigDecimal.valueOf(l);
        if (val instanceof Integer i) return BigDecimal.valueOf(i.longValue());
        if (val instanceof Number n) return BigDecimal.valueOf(n.doubleValue());
        try { return new BigDecimal(val.toString()); }
        catch (Exception e) { return BigDecimal.ZERO; }
    }

    private Long toLong(Object val) {
        if (val == null) return 0L;
        if (val instanceof Number n) return n.longValue();
        try { return new BigDecimal(val.toString()).longValue(); }
        catch (Exception e) { return 0L; }
    }
}
