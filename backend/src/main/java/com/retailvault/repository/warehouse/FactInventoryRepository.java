package com.retailvault.repository.warehouse;

import com.retailvault.entity.warehouse.FactInventory;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface FactInventoryRepository extends JpaRepository<FactInventory, Long> {

    @Query(value = """
        SELECT TOP 20 dp.product_name, ds.store_name,
               COALESCE(SUM(fs.quantity), 0),
               AVG(fi.stock_after),
               MIN(fi.stock_after)
        FROM fact_inventory fi
        JOIN dim_product dp ON fi.product_key = dp.product_key
        JOIN dim_store ds ON fi.store_key = ds.store_key
        LEFT JOIN fact_sales fs ON fs.product_key = fi.product_key AND fs.store_key = fi.store_key
        GROUP BY dp.product_name, ds.store_name
        ORDER BY COALESCE(SUM(fs.quantity), 0) DESC
    """, nativeQuery = true)
    List<Object[]> getInventoryTurnover();

    @Query(value = """
        SELECT dp.product_name, ds.store_name,
               fi.stock_after, fi.reorder_level
        FROM fact_inventory fi
        JOIN dim_product dp ON fi.product_key = dp.product_key
        JOIN dim_store ds ON fi.store_key = ds.store_key
        WHERE fi.is_below_reorder = 1
        ORDER BY fi.stock_after ASC
    """, nativeQuery = true)
    List<Object[]> getLowStockAlerts();

    @Query(value = """
        SELECT fi.movement_type, SUM(fi.quantity_moved),
               COUNT(*)
        FROM fact_inventory fi
        JOIN dim_date dd ON fi.date_key = dd.date_key
        WHERE dd.year = :year
        GROUP BY fi.movement_type
    """, nativeQuery = true)
    List<Object[]> getInventoryMovementSummary(Integer year);
}
