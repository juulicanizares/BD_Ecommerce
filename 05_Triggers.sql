-- =====================================================================
-- 05_Triggers.sql
-- =====================================================================

USE ecommerce_db;

-- ---------------------------------------------------------------------
-- TABLAS AUXILIARES DE AUDITORÍA Y ALERTAS
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auditoria_precios (
    id_auditoria INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    precio_anterior DECIMAL(12,2),
    precio_nuevo DECIMAL(12,2),
    fecha_cambio DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS auditoria_clientes (
    id_auditoria INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    email VARCHAR(150),
    fecha_registro DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS auditoria_estado_pedidos (
    id_auditoria INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT NOT NULL,
    estado_anterior VARCHAR(50),
    estado_nuevo VARCHAR(50),
    fecha_cambio DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS auditoria_permisos (
    id_auditoria INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NOT NULL,
    permiso_anterior VARCHAR(100),
    permiso_nuevo VARCHAR(100),
    fecha_cambio DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS alertas_stock (
    id_alerta INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    stock_actual INT NOT NULL,
    mensaje VARCHAR(255),
    fecha_alerta DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ventas_archivadas (
    id_venta INT PRIMARY KEY,
    id_cliente INT,
    fecha_venta DATETIME,
    total DECIMAL(14,2),
    estado VARCHAR(50),
    fecha_eliminacion DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS permisos_usuario (
    id_usuario INT NOT NULL PRIMARY KEY,
    permiso VARCHAR(100) NOT NULL
) ENGINE = InnoDB COMMENT = 'Tabla de permisos de usuarios para auditoría';

-- ---------------------------------------------------------------------
-- 1. trg_audit_precio_producto_after_update
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_audit_precio_producto_after_update;
DELIMITER //
CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.precio <> NEW.precio THEN
        INSERT INTO auditoria_precios (id_producto, precio_anterior, precio_nuevo)
        VALUES (OLD.id_producto, OLD.precio, NEW.precio);
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 2. trg_check_stock_before_insert_venta
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_check_stock_before_insert_venta;
DELIMITER //
CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    DECLARE v_stock INT;
    SELECT stock INTO v_stock FROM productos WHERE id_producto = NEW.id_producto;
    IF v_stock IS NULL OR v_stock < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Stock insuficiente para registrar este detalle de venta.';
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3. trg_update_stock_after_insert_venta
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_stock_after_insert_venta;
DELIMITER //
CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE productos
       SET stock = stock - NEW.cantidad
     WHERE id_producto = NEW.id_producto;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 4. trg_prevent_delete_categoria_with_products
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_delete_categoria_with_products;
DELIMITER //
CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    DECLARE v_conteo INT;
    SELECT COUNT(*) INTO v_conteo FROM productos WHERE id_categoria = OLD.id_categoria;
    IF v_conteo > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede eliminar la categoria porque tiene productos asociados.';
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 5. trg_log_new_customer_after_insert
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_log_new_customer_after_insert;
DELIMITER //
CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_clientes (id_cliente, email)
    VALUES (NEW.id_cliente, NEW.email);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 6. trg_update_total_gastado_cliente
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_total_gastado_cliente;
DELIMITER //
CREATE TRIGGER trg_update_total_gastado_cliente
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado = 'Completado' AND OLD.estado <> 'Completado' THEN
        UPDATE clientes
           SET total_gastado = COALESCE(total_gastado, 0) + NEW.total
         WHERE id_cliente = NEW.id_cliente;
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 7. trg_set_fecha_modificacion_producto
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_set_fecha_modificacion_producto;
DELIMITER //
CREATE TRIGGER trg_set_fecha_modificacion_producto
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    SET NEW.fecha_modificacion = NOW();
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 8. trg_prevent_negative_stock
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_negative_stock;
DELIMITER //
CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El stock de un producto no puede ser un valor negativo.';
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 9. trg_capitalize_nombre_cliente
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_capitalize_nombre_cliente;
DELIMITER //
CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NEW.nombre IS NOT NULL THEN
        SET NEW.nombre = CONCAT(UPPER(LEFT(NEW.nombre, 1)), LOWER(SUBSTRING(NEW.nombre, 2)));
    END IF;
    IF NEW.apellido IS NOT NULL THEN
        SET NEW.apellido = CONCAT(UPPER(LEFT(NEW.apellido, 1)), LOWER(SUBSTRING(NEW.apellido, 2)));
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 10. trg_recalculate_total_venta_on_detalle_change
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_recalculate_total_venta_on_detalle_change;
DELIMITER //
CREATE TRIGGER trg_recalculate_total_venta_on_detalle_change
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
       SET total = (
           SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0)
             FROM detalle_ventas
            WHERE id_venta = NEW.id_venta
       )
     WHERE id_venta = NEW.id_venta;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 11. trg_log_order_status_change
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_log_order_status_change;
DELIMITER //
CREATE TRIGGER trg_log_order_status_change
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF OLD.estado <> NEW.estado THEN
        INSERT INTO auditoria_estado_pedidos (id_venta, estado_anterior, estado_nuevo)
        VALUES (NEW.id_venta, OLD.estado, NEW.estado);
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 12. trg_prevent_price_zero_or_less
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_price_zero_or_less;
DELIMITER //
CREATE TRIGGER trg_prevent_price_zero_or_less
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El precio del producto debe ser mayor a cero.';
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 13. trg_send_stock_alert_on_low_stock
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_send_stock_alert_on_low_stock;
DELIMITER //
CREATE TRIGGER trg_send_stock_alert_on_low_stock
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock <= 5 AND OLD.stock > 5 THEN
        INSERT INTO alertas_stock (id_producto, stock_actual, mensaje)
        VALUES (NEW.id_producto, NEW.stock, CONCAT('Atencion: Stock bajo para el producto ID ', NEW.id_producto));
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 14. trg_archive_deleted_venta
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_archive_deleted_venta;
DELIMITER //
CREATE TRIGGER trg_archive_deleted_venta
BEFORE DELETE ON ventas
FOR EACH ROW
BEGIN
    INSERT INTO ventas_archivadas (id_venta, id_cliente, fecha_venta, total, estado)
    VALUES (OLD.id_venta, OLD.id_cliente, OLD.fecha_venta, OLD.total, OLD.estado);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 15. trg_validate_email_format_on_customer
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_validate_email_format_on_customer;
DELIMITER //
CREATE TRIGGER trg_validate_email_format_on_customer
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NEW.email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El formato del correo electronico no es valido.';
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 16. trg_update_last_order_date_customer
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_last_order_date_customer;
DELIMITER //
CREATE TRIGGER trg_update_last_order_date_customer
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    UPDATE clientes
       SET ultima_fecha_compra = NEW.fecha_venta
     WHERE id_cliente = NEW.id_cliente;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 17. trg_prevent_self_referral
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_self_referral;
DELIMITER //
CREATE TRIGGER trg_prevent_self_referral
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NEW.referido_por IS NOT NULL AND NEW.referido_por = NEW.id_cliente THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Un cliente no puede referenciarse a si mismo.';
    END IF;
END//
DELIMITER ;
-- ---------------------------------------------------------------------
-- 18. trg_log_permission_changes
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_log_permission_changes;
DELIMITER //
CREATE TRIGGER trg_log_permission_changes
AFTER UPDATE ON permisos_usuario
FOR EACH ROW
BEGIN
    IF OLD.permiso <> NEW.permiso THEN
        INSERT INTO auditoria_permisos (id_usuario, permiso_anterior, permiso_nuevo)
        VALUES (NEW.id_usuario, OLD.permiso, NEW.permiso);
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 19. trg_assign_default_category_on_null
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_assign_default_category_on_null;
DELIMITER //
CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.id_categoria IS NULL THEN
        SET NEW.id_categoria = 1; -- ID correspondiente a Categoria General
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 20. trg_update_producto_count_in_categoria
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_update_producto_count_in_categoria;
DELIMITER //
CREATE TRIGGER trg_update_producto_count_in_categoria
AFTER INSERT ON productos
FOR EACH ROW
BEGIN
    UPDATE categorias
       SET total_productos = COALESCE(total_productos, 0) + 1
     WHERE id_categoria = NEW.id_categoria;
END//
DELIMITER ;