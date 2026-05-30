package com.retailvault.etl;

import com.retailvault.entity.warehouse.EtlRunLog;
import com.retailvault.repository.warehouse.EtlRunLogRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

import javax.sql.DataSource;
import java.sql.*;
import java.time.LocalDateTime;

/**
 * RetailVault ETL Pipeline Service — SQL Server edition.
 *
 * All heavy ETL logic has been moved into usp_RunEtlPipeline (T-SQL stored procedure).
 * This service is a thin Java wrapper that:
 *   1. Calls the stored procedure via JDBC
 *   2. Reads back the run_id and rows_loaded from the proc's result set
 *   3. Syncs the result into the JPA-managed etl_run_log for the REST API
 *
 * Benefits of this architecture:
 *   - Full T-SQL transaction management (ACID) inside the proc
 *   - Execution plan caching — SQL Server compiles usp_RunEtlPipeline once
 *   - Easier DBA visibility: sp_who2, sys.dm_exec_requests show the proc name
 *   - Java layer stays thin; DB team can tune the proc without a redeploy
 */
@Slf4j
@Service
public class EtlPipelineService {

    // Direct JDBC DataSource (warehouse DB) — bypasses JPA for stored proc calls
    private final DataSource warehouseDataSource;
    private final EtlRunLogRepository etlRunLogRepository;

    @org.springframework.beans.factory.annotation.Autowired
    public EtlPipelineService(
            @Qualifier("warehouseDataSource") DataSource warehouseDataSource,
            EtlRunLogRepository etlRunLogRepository) {
        this.warehouseDataSource = warehouseDataSource;
        this.etlRunLogRepository = etlRunLogRepository;
    }

    // ============================================================
    // Public entry point — called by EtlScheduler and EtlController
    // ============================================================
    public EtlRunLog runFullEtl(String triggeredBy) {
        log.info("Invoking usp_RunEtlPipeline via JDBC [triggeredBy={}]", triggeredBy);

        Long  dbRunId   = null;
        int   rowsLoaded = 0;
        String status   = "FAILED";
        String errMsg   = null;

        try (Connection conn = warehouseDataSource.getConnection();
             CallableStatement cs = conn.prepareCall("{call usp_RunEtlPipeline(?)}")) {

            cs.setString(1, triggeredBy);

            // Proc returns a single-row result set: run_id, rows_loaded
            boolean hasResults = cs.execute();
            if (hasResults) {
                try (ResultSet rs = cs.getResultSet()) {
                    if (rs.next()) {
                        dbRunId    = rs.getLong("run_id");
                        rowsLoaded = rs.getInt("rows_loaded");
                    }
                }
            }
            status = "SUCCESS";
            log.info("ETL stored procedure completed. run_id={}, rows_loaded={}", dbRunId, rowsLoaded);

        } catch (SQLException ex) {
            errMsg = ex.getMessage();
            log.error("ETL stored procedure failed: {}", errMsg, ex);
        }

        // Sync result back to JPA-managed etl_run_log for the analytics REST API
        return syncRunLog(dbRunId, triggeredBy, status, rowsLoaded, errMsg);
    }

    // ============================================================
    // Sync the DB-side run log row into JPA so the REST layer
    // can query it through EtlRunLogRepository without raw SQL.
    // ============================================================
    private EtlRunLog syncRunLog(Long dbRunId, String triggeredBy,
                                  String status, int rowsLoaded, String errMsg) {
        // Try to load the row that the stored proc inserted
        EtlRunLog log2 = (dbRunId != null)
                ? etlRunLogRepository.findById(dbRunId).orElse(new EtlRunLog())
                : new EtlRunLog();

        if (log2.getRunId() == null) {
            // Fallback: proc failed before inserting — create record in Java
            log2.setJobName("FULL_ETL");
            log2.setStartedAt(LocalDateTime.now());
            log2.setTriggeredBy(triggeredBy);
        }

        log2.setStatus(status);
        log2.setRowsLoaded(rowsLoaded);
        log2.setRowsExtracted(rowsLoaded);
        if (log2.getCompletedAt() == null) log2.setCompletedAt(LocalDateTime.now());
        if (errMsg != null) log2.setErrorMessage(errMsg);

        return etlRunLogRepository.save(log2);
    }
}
