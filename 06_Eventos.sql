-- =====================================================================
-- 06_Eventos.sql
-- =====================================================================

USE ecommerce_db;

-- Habilitar el Programador de Eventos en MySQL
SET GLOBAL event_scheduler = ON;

-- ---------------------------------------------------------------------
-- TABLAS AUXILIARES PARA REPORTES, LOGS Y KPIS
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reporte_ventas_semanal (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    fecha_inicio DATE,
    fecha_fin DATE,
    total_ventas DECIMAL(14,2),
    cantidad_pedidos INT,
    fecha_generacion DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS registros_temporales (
    id INT AUTO_INCREMENT PRIMARY KEY,
    datos TEXT,
    fecha_creacion DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS historico_auditoria_precios LIKE auditoria_precios;

CREATE TABLE IF NOT EXISTS promociones (
    id_promocion INT AUTO_INCREMENT PRIMARY KEY,
    codigo VARCHAR(50),
    descuento DECIMAL(5,2),
    fecha_fin DATETIME,
    activa BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS lista_reabastecimiento (
    id_reabastecimiento INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT,
    stock_actual INT,
    fecha_registro DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS resumen_ventas_diarias (
    fecha DATE PRIMARY KEY,
    total_monto DECIMAL(14,2),
    total_pedidos INT
);

CREATE TABLE IF NOT EXISTS alertas_inconsistencia (
    id_alerta INT AUTO_INCREMENT PRIMARY KEY,
    tipo VARCHAR(100),
    descripcion TEXT,
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS cupones_cumpleanos (
    id_cupon INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT,
    codigo_cupon VARCHAR(50),
    fecha_emision DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ranking_productos (
    posicion INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT,
    total_vendido INT
);

CREATE TABLE IF NOT EXISTS carritos (
    id_carrito INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT,
    fecha_ultima_actividad DATETIME,
    estado VARCHAR(20) DEFAULT 'Activo'
);

CREATE TABLE IF NOT EXISTS kpis_mensuales (
    id_kpi INT AUTO_INCREMENT PRIMARY KEY,
    mes_año VARCHAR(7),
    ingresos_totales DECIMAL(14,2),
    nuevos_clientes INT,
    ticket_promedio DECIMAL(12,2),
    fecha_calculo DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS mv_resumen_inventario (
    id_categoria INT PRIMARY KEY,
    total_productos INT,
    stock_total INT,
    fecha_actualizacion DATETIME
);

CREATE TABLE IF NOT EXISTS log_tamano_db (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    tamano_mb DECIMAL(10,2),
    fecha_registro DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS alertas_fraude (
    id_fraude INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT,
    motivo VARCHAR(255),
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS reporte_proveedores (
    id_reporte INT AUTO_INCREMENT PRIMARY KEY,
    id_proveedor INT,
    mes_año VARCHAR(7),
    total_suministrado INT,
    fecha_generacion DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 1. evt_generate_weekly_sales_report
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_generate_weekly_sales_report;
DELIMITER //
CREATE EVENT evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO reporte_ventas_semanal (fecha_inicio, fecha_fin, total_ventas, cantidad_pedidos)
    SELECT 
        DATE_SUB(CURDATE(), INTERVAL 7 DAY),
        CURDATE(),
        COALESCE(SUM(total), 0),
        COUNT(*)
    FROM ventas
    WHERE fecha_venta >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
      AND estado <> 'Cancelado';
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 2. evt_cleanup_temp_tables_daily
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_cleanup_temp_tables_daily;
DELIMITER //
CREATE EVENT evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    DELETE FROM registros_temporales 
     WHERE fecha_creacion < DATE_SUB(NOW(), INTERVAL 1 DAY);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3. evt_archive_old_logs_monthly
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_archive_old_logs_monthly;
DELIMITER //
CREATE EVENT evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO historico_auditoria_precios
    SELECT * FROM auditoria_precios 
     WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);

    DELETE FROM auditoria_precios 
     WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 4. evt_deactivate_expired_promotions_hourly
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_deactivate_expired_promotions_hourly;
DELIMITER //
CREATE EVENT evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    UPDATE promociones
       SET activa = FALSE
     WHERE fecha_fin < NOW() AND activa = TRUE;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 5. evt_recalculate_customer_loyalty_tiers_nightly
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_recalculate_customer_loyalty_tiers_nightly;
DELIMITER //
CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY
STARTS '2026-01-01 02:00:00'
DO
BEGIN
    UPDATE clientes
       SET nivel_lealtad = fn_DeterminarEstadoLealtad(id_cliente);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 6. evt_generate_reorder_list_daily
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_generate_reorder_list_daily;
DELIMITER //
CREATE EVENT evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    TRUNCATE TABLE lista_reabastecimiento;
    INSERT INTO lista_reabastecimiento (id_producto, stock_actual)
    SELECT id_producto, stock 
      FROM productos 
     WHERE stock <= 5 AND activo = TRUE;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 7. evt_rebuild_indexes_weekly
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_rebuild_indexes_weekly;
DELIMITER //
CREATE EVENT evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    OPTIMIZE TABLE productos, clientes, ventas, detalle_ventas;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 8. evt_suspend_inactive_accounts_quarterly
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_suspend_inactive_accounts_quarterly;
DELIMITER //
CREATE EVENT evt_suspend_inactive_accounts_quarterly
ON SCHEDULE EVERY 3 MONTH
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    UPDATE clientes
       SET activo = FALSE
     WHERE ultima_fecha_compra < DATE_SUB(NOW(), INTERVAL 1 YEAR)
        OR (ultima_fecha_compra IS NULL AND fecha_registro < DATE_SUB(NOW(), INTERVAL 1 YEAR));
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 9. evt_aggregate_daily_sales_data
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_aggregate_daily_sales_data;
DELIMITER //
CREATE EVENT evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY
STARTS '2026-01-01 23:59:00'
DO
BEGIN
    INSERT INTO resumen_ventas_diarias (fecha, total_monto, total_pedidos)
    SELECT 
        CURDATE(),
        COALESCE(SUM(total), 0),
        COUNT(*)
    FROM ventas
    WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado'
    ON DUPLICATE KEY UPDATE 
        total_monto = VALUES(total_monto),
        total_pedidos = VALUES(total_pedidos);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 10. evt_check_data_consistency_nightly
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_check_data_consistency_nightly;
DELIMITER //
CREATE EVENT evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY
STARTS '2026-01-01 03:00:00'
DO
BEGIN
    -- Detectar ventas sin detalle
    INSERT INTO alertas_inconsistencia (tipo, descripcion)
    SELECT 'Venta huérfana', CONCAT('Venta ID ', v.id_venta, ' no tiene detalles registrados.')
      FROM ventas v
 LEFT JOIN detalle_ventas dv ON v.id_venta = dv.id_venta
     WHERE dv.id_venta IS NULL;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 11. evt_send_birthday_greetings_daily
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_send_birthday_greetings_daily;
DELIMITER //
CREATE EVENT evt_send_birthday_greetings_daily
ON SCHEDULE EVERY 1 DAY
STARTS '2026-01-01 08:00:00'
DO
BEGIN
    INSERT INTO cupones_cumpleanos (id_cliente, codigo_cupon)
    SELECT id_cliente, CONCAT('HB-2026-', id_cliente)
      FROM clientes
     WHERE MONTH(fecha_nacimiento) = MONTH(CURDATE())
       AND DAY(fecha_nacimiento) = DAY(CURDATE());
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 12. evt_update_product_rankings_hourly
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_update_product_rankings_hourly;
DELIMITER //
CREATE EVENT evt_update_product_rankings_hourly
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    TRUNCATE TABLE ranking_productos;
    INSERT INTO ranking_productos (id_producto, total_vendido)
    SELECT id_producto, SUM(cantidad) AS total
      FROM detalle_ventas
  GROUP BY id_producto
  ORDER BY total DESC
     LIMIT 10;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 13. evt_backup_critical_tables_daily
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_backup_critical_tables_daily;
DELIMITER //
CREATE EVENT evt_backup_critical_tables_daily
ON SCHEDULE EVERY 1 DAY
STARTS '2026-01-01 01:00:00'
DO
BEGIN
    -- Generar copia lógica de auditoría
    INSERT INTO historico_auditoria_precios SELECT * FROM auditoria_precios ON DUPLICATE KEY UPDATE id_auditoria=id_auditoria;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 14. evt_clear_abandoned_carts_daily
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_clear_abandoned_carts_daily;
DELIMITER //
CREATE EVENT evt_clear_abandoned_carts_daily
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    DELETE FROM carritos
     WHERE estado = 'Abandonado' OR fecha_ultima_actividad < DATE_SUB(NOW(), INTERVAL 72 HOUR);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 15. evt_calculate_monthly_kpis
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_calculate_monthly_kpis;
DELIMITER //
CREATE EVENT evt_calculate_monthly_kpis
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    DECLARE v_mes VARCHAR(7);
    SET v_mes = DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 1 MONTH), '%Y-%m');

    INSERT INTO kpis_mensuales (mes_año, ingresos_totales, nuevos_clientes, ticket_promedio)
    SELECT 
        v_mes,
        COALESCE(SUM(total), 0),
        (SELECT COUNT(*) FROM clientes WHERE DATE_FORMAT(fecha_registro, '%Y-%m') = v_mes),
        COALESCE(AVG(total), 0)
    FROM ventas
    WHERE DATE_FORMAT(fecha_venta, '%Y-%m') = v_mes AND estado <> 'Cancelado';
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 16. evt_refresh_materialized_views_nightly
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_refresh_materialized_views_nightly;
DELIMITER //
CREATE EVENT evt_refresh_materialized_views_nightly
ON SCHEDULE EVERY 1 DAY
STARTS '2026-01-01 04:00:00'
DO
BEGIN
    TRUNCATE TABLE mv_resumen_inventario;
    INSERT INTO mv_resumen_inventario (id_categoria, total_productos, stock_total, fecha_actualizacion)
    SELECT c.id_categoria, COUNT(p.id_producto), COALESCE(SUM(p.stock), 0), NOW()
      FROM categorias c
 LEFT JOIN productos p ON c.id_categoria = p.id_categoria
  GROUP BY c.id_categoria;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 17. evt_log_database_size_weekly
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_log_database_size_weekly;
DELIMITER //
CREATE EVENT evt_log_database_size_weekly
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO log_tamano_db (tamano_mb)
    SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
      FROM information_schema.tables
     WHERE table_schema = 'ecommerce_db';
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 18. evt_detect_fraudulent_activity_hourly
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_detect_fraudulent_activity_hourly;
DELIMITER //
CREATE EVENT evt_detect_fraudulent_activity_hourly
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    INSERT INTO alertas_fraude (id_cliente, motivo)
    SELECT id_cliente, 'Mas de 3 ventas canceladas en la ultima hora'
      FROM ventas
     WHERE estado = 'Cancelado' AND fecha_venta >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
  GROUP BY id_cliente
    HAVING COUNT(*) >= 3;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 19. evt_generate_supplier_performance_report_monthly
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_generate_supplier_performance_report_monthly;
DELIMITER //
CREATE EVENT evt_generate_supplier_performance_report_monthly
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    DECLARE v_mes VARCHAR(7);
    SET v_mes = DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 1 MONTH), '%Y-%m');

    INSERT INTO reporte_proveedores (id_proveedor, mes_año, total_suministrado)
    SELECT p.id_proveedor, v_mes, COALESCE(SUM(p.stock), 0)
      FROM productos p
     WHERE p.id_proveedor IS NOT NULL
  GROUP BY p.id_proveedor;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 20. evt_purge_soft_deleted_records_weekly
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_purge_soft_deleted_records_weekly;
DELIMITER //
CREATE EVENT evt_purge_soft_deleted_records_weekly
ON SCHEDULE EVERY 1 WEEK
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    DELETE FROM productos 
     WHERE activo = FALSE AND fecha_modificacion < DATE_SUB(NOW(), INTERVAL 30 DAY);
END//
DELIMITER ;