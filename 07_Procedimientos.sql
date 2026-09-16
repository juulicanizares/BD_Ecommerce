-- =====================================================================
-- 07_Procedimientos.sql
-- =====================================================================

USE ecommerce_db;

-- ---------------------------------------------------------------------
-- TABLAS AUXILIARES REQUERIDAS
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS creditos_cliente (
    id_credito INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT,
    monto DECIMAL(12,2),
    motivo VARCHAR(255),
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ajustes_stock (
    id_ajuste INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT,
    stock_anterior INT,
    stock_nuevo INT,
    motivo VARCHAR(255),
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS resenas_productos (
    id_resena INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT,
    id_producto INT,
    calificacion INT,
    comentario TEXT,
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pagos (
    id_pago INT AUTO_INCREMENT PRIMARY KEY,
    id_venta INT,
    metodo_pago VARCHAR(50),
    monto DECIMAL(14,2),
    fecha_pago DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 1. sp_RealizarNuevaVenta
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_RealizarNuevaVenta;
DELIMITER //
CREATE PROCEDURE sp_RealizarNuevaVenta(
    IN p_id_cliente INT,
    IN p_id_sucursal INT,
    OUT p_id_venta INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
        INSERT INTO ventas (id_cliente, id_sucursal, fecha_venta, estado, total)
        VALUES (p_id_cliente, p_id_sucursal, NOW(), 'Pendiente', 0.00);

        SET p_id_venta = LAST_INSERT_ID();
    COMMIT;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 2. sp_AgregarNuevoProducto
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AgregarNuevoProducto;
DELIMITER //
CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN p_nombre VARCHAR(150),
    IN p_precio DECIMAL(12,2),
    IN p_stock INT,
    IN p_id_categoria INT,
    IN p_id_proveedor INT
)
BEGIN
    IF p_precio <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El precio debe ser mayor a cero.';
    END IF;

    INSERT INTO productos (nombre, precio, stock, id_categoria, id_proveedor, activo)
    VALUES (p_nombre, p_precio, p_stock, p_id_categoria, p_id_proveedor, TRUE);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3. sp_ActualizarDireccionCliente
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ActualizarDireccionCliente;
DELIMITER //
CREATE PROCEDURE sp_ActualizarDireccionCliente(
    IN p_id_cliente INT,
    IN p_nueva_direccion TEXT,
    IN p_ciudad VARCHAR(100)
)
BEGIN
    UPDATE clientes
       SET direccion = p_nueva_direccion,
           ciudad = p_ciudad
     WHERE id_cliente = p_id_cliente;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 4. sp_ProcesarDevolucion
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion;
DELIMITER //
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN p_id_venta INT,
    IN p_id_producto INT,
    IN p_cantidad INT
)
BEGIN
    DECLARE v_id_cliente INT;
    DECLARE v_precio DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT id_cliente INTO v_id_cliente FROM ventas WHERE id_venta = p_id_venta;
    SELECT precio_unitario_congelado INTO v_precio 
      FROM detalle_ventas 
     WHERE id_venta = p_id_venta AND id_producto = p_id_producto;

    START TRANSACTION;
        -- Reintegrar stock
        UPDATE productos SET stock = stock + p_cantidad WHERE id_producto = p_id_producto;

        -- Generar saldo a favor
        INSERT INTO creditos_cliente (id_cliente, monto, motivo)
        VALUES (v_id_cliente, (v_precio * p_cantidad), CONCAT('Devolución de producto en venta #', p_id_venta));
    COMMIT;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 5. sp_ObtenerHistorialComprasCliente
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerHistorialComprasCliente;
DELIMITER //
CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(IN p_id_cliente INT)
BEGIN
    SELECT 
        v.id_venta,
        v.fecha_venta,
        v.estado,
        v.total,
        COUNT(dv.id_detalle) AS total_items
    FROM ventas v
    LEFT JOIN detalle_ventas dv ON v.id_venta = dv.id_venta
    WHERE v.id_cliente = p_id_cliente
    GROUP BY v.id_venta, v.fecha_venta, v.estado, v.total
    ORDER BY v.fecha_venta DESC;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 6. sp_AjustarNivelStock
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AjustarNivelStock;
DELIMITER //
CREATE PROCEDURE sp_AjustarNivelStock(
    IN p_id_producto INT,
    IN p_nuevo_stock INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    DECLARE v_stock_actual INT;

    SELECT stock INTO v_stock_actual FROM productos WHERE id_producto = p_id_producto;

    START TRANSACTION;
        INSERT INTO ajustes_stock (id_producto, stock_anterior, stock_nuevo, motivo)
        VALUES (p_id_producto, v_stock_actual, p_nuevo_stock, p_motivo);

        UPDATE productos SET stock = p_nuevo_stock WHERE id_producto = p_id_producto;
    COMMIT;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 7. sp_EliminarClienteDeFormaSegura
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_EliminarClienteDeFormaSegura;
DELIMITER //
CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(IN p_id_cliente INT)
BEGIN
    UPDATE clientes
       SET nombre = 'ANÓNIMO',
           apellido = 'ANÓNIMO',
           email = CONCAT('anonimo_', p_id_cliente, '@deleted.com'),
           telefono = NULL,
           direccion = NULL,
           activo = FALSE
     WHERE id_cliente = p_id_cliente;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 8. sp_AplicarDescuentoPorCategoria
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AplicarDescuentoPorCategoria;
DELIMITER //
CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(
    IN p_id_categoria INT,
    IN p_porcentaje DECIMAL(5,2)
)
BEGIN
    UPDATE productos
       SET precio = fn_AplicarDescuento(precio, p_porcentaje)
     WHERE id_categoria = p_id_categoria AND activo = TRUE;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 9. sp_GenerarReporteMensualVentas
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_GenerarReporteMensualVentas;
DELIMITER //
CREATE PROCEDURE sp_GenerarReporteMensualVentas(
    IN p_mes INT,
    IN p_anio INT
)
BEGIN
    SELECT 
        COUNT(id_venta) AS total_pedidos,
        COALESCE(SUM(total), 0) AS ingresos_totales,
        COALESCE(AVG(total), 0) AS ticket_promedio
    FROM ventas
    WHERE MONTH(fecha_venta) = p_mes 
      AND YEAR(fecha_venta) = p_anio 
      AND estado <> 'Cancelado';
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 10. sp_CambiarEstadoPedido
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_CambiarEstadoPedido;
DELIMITER //
CREATE PROCEDURE sp_CambiarEstadoPedido(
    IN p_id_venta INT,
    IN p_nuevo_estado VARCHAR(50)
)
BEGIN
    UPDATE ventas
       SET estado = p_nuevo_estado
     WHERE id_venta = p_id_venta;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 11. sp_RegistrarNuevoCliente
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_RegistrarNuevoCliente;
DELIMITER //
CREATE PROCEDURE sp_RegistrarNuevoCliente(
    IN p_nombre VARCHAR(80),
    IN p_apellido VARCHAR(80),
    IN p_email VARCHAR(150),
    IN p_telefono VARCHAR(20)
)
BEGIN
    DECLARE v_existe INT;

    SELECT COUNT(*) INTO v_existe FROM clientes WHERE email = p_email;

    IF v_existe > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El correo electrónico ya se encuentra registrado.';
    END IF;

    INSERT INTO clientes (nombre, apellido, email, telefono, fecha_registro, activo)
    VALUES (p_nombre, p_apellido, p_email, p_telefono, NOW(), TRUE);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 12. sp_ObtenerDetallesProductoCompleto
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerDetallesProductoCompleto;
DELIMITER //
CREATE PROCEDURE sp_ObtenerDetallesProductoCompleto(IN p_id_producto INT)
BEGIN
    SELECT 
        p.id_producto,
        p.nombre AS producto,
        p.precio,
        p.stock,
        c.nombre AS categoria,
        pr.nombre AS proveedor
    FROM productos p
    LEFT JOIN categorias c ON p.id_categoria = c.id_categoria
    LEFT JOIN proveedores pr ON p.id_proveedor = pr.id_proveedor
    WHERE p.id_producto = p_id_producto;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 13. sp_FusionarCuentasCliente
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_FusionarCuentasCliente;
DELIMITER //
CREATE PROCEDURE sp_FusionarCuentasCliente(
    IN p_id_cliente_origen INT,
    IN p_id_cliente_destino INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
        -- Transferir historial de ventas
        UPDATE ventas SET id_cliente = p_id_cliente_destino WHERE id_cliente = p_id_cliente_origen;

        -- Desactivar cuenta de origen
        UPDATE clientes SET activo = FALSE, nombre = CONCAT('FUSIONADO CON ID ', p_id_cliente_destino) WHERE id_cliente = p_id_cliente_origen;
    COMMIT;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 14. sp_AsignarProductoAProveedor
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AsignarProductoAProveedor;
DELIMITER //
CREATE PROCEDURE sp_AsignarProductoAProveedor(
    IN p_id_producto INT,
    IN p_id_proveedor INT
)
BEGIN
    UPDATE productos
       SET id_proveedor = p_id_proveedor
     WHERE id_producto = p_id_producto;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 15. sp_BuscarProductos
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_BuscarProductos;
DELIMITER //
CREATE PROCEDURE sp_BuscarProductos(
    IN p_busqueda VARCHAR(100),
    IN p_id_categoria INT,
    IN p_precio_min DECIMAL(12,2),
    IN p_precio_max DECIMAL(12,2)
)
BEGIN
    SELECT id_producto, nombre, precio, stock, id_categoria
      FROM productos
     WHERE (p_busqueda IS NULL OR nombre LIKE CONCAT('%', p_busqueda, '%'))
       AND (p_id_categoria IS NULL OR id_categoria = p_id_categoria)
       AND (p_precio_min IS NULL OR precio >= p_precio_min)
       AND (p_precio_max IS NULL OR precio <= p_precio_max)
       AND activo = TRUE;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 16. sp_ObtenerDashboardAdmin
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerDashboardAdmin;
DELIMITER //
CREATE PROCEDURE sp_ObtenerDashboardAdmin()
BEGIN
    SELECT 
        (SELECT COALESCE(SUM(total),0) FROM ventas WHERE DATE(fecha_venta) = CURDATE() AND estado <> 'Cancelado') AS ventas_hoy,
        (SELECT COUNT(*) FROM clientes WHERE DATE(fecha_registro) = CURDATE()) AS nuevos_clientes_hoy,
        (SELECT COUNT(*) FROM ventas WHERE estado = 'Pendiente') AS pedidos_pendientes,
        (SELECT COUNT(*) FROM productos WHERE stock <= 5) AS alertas_stock_critico;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 17. sp_ProcesarPago
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ProcesarPago;
DELIMITER //
CREATE PROCEDURE sp_ProcesarPago(
    IN p_id_venta INT,
    IN p_metodo_pago VARCHAR(50)
)
BEGIN
    DECLARE v_monto DECIMAL(14,2);

    SELECT total INTO v_monto FROM ventas WHERE id_venta = p_id_venta;

    START TRANSACTION;
        INSERT INTO pagos (id_venta, metodo_pago, monto)
        VALUES (p_id_venta, p_metodo_pago, v_monto);

        UPDATE ventas SET estado = 'Pagado' WHERE id_venta = p_id_venta;
    COMMIT;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 18. sp_AñadirReseñaProducto
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AñadirReseñaProducto;
DELIMITER //
CREATE PROCEDURE sp_AñadirReseñaProducto(
    IN p_id_cliente INT,
    IN p_id_producto INT,
    IN p_calificacion INT,
    IN p_comentario TEXT
)
BEGIN
    DECLARE v_compro INT;

    -- Validar que el cliente haya comprado el producto
    SELECT COUNT(*) INTO v_compro
      FROM ventas v
      JOIN detalle_ventas dv ON v.id_venta = dv.id_venta
     WHERE v.id_cliente = p_id_cliente 
       AND dv.id_producto = p_id_producto 
       AND v.estado <> 'Cancelado';

    IF v_compro = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El cliente solo puede opinar sobre productos que ha comprado.';
    END IF;

    INSERT INTO resenas_productos (id_cliente, id_producto, calificacion, comentario)
    VALUES (p_id_cliente, p_id_producto, p_calificacion, p_comentario);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 19. sp_ObtenerProductosRelacionados
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_ObtenerProductosRelacionados;
DELIMITER //
CREATE PROCEDURE sp_ObtenerProductosRelacionados(IN p_id_producto INT)
BEGIN
    SELECT 
        dv2.id_producto,
        p.nombre,
        COUNT(*) AS veces_comprado_junto
    FROM detalle_ventas dv1
    JOIN detalle_ventas dv2 ON dv1.id_venta = dv2.id_venta AND dv1.id_producto <> dv2.id_producto
    JOIN productos p ON dv2.id_producto = p.id_producto
    WHERE dv1.id_producto = p_id_producto
    GROUP BY dv2.id_producto, p.nombre
    ORDER BY veces_comprado_junto DESC
    LIMIT 5;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 20. sp_MoverProductosEntreCategorias
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_MoverProductosEntreCategorias;
DELIMITER //
CREATE PROCEDURE sp_MoverProductosEntreCategorias(
    IN p_id_categoria_origen INT,
    IN p_id_categoria_destino INT
)
BEGIN
    UPDATE productos
       SET id_categoria = p_id_categoria_destino
     WHERE id_categoria = p_id_categoria_origen;
END//
DELIMITER ;