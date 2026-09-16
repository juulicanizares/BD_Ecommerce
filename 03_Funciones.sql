-- =====================================================================
-- 03_Funciones.sql
-- =====================================================================

USE ecommerce_db;

SET GLOBAL log_bin_trust_function_creators = 1;

-- ---------------------------------------------------------------------
-- 1. fn_CalcularTotalVenta
-- Calcula el monto total de una venta a partir de su detalle.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularTotalVenta;
DELIMITER //
CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT)
RETURNS DECIMAL(14,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(14,2);
    SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0)
      INTO v_total
      FROM detalle_ventas
     WHERE id_venta = p_id_venta;
    RETURN v_total;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 2. fn_VerificarDisponibilidadStock
-- Valida si hay stock suficiente de un producto para una cantidad dada.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_VerificarDisponibilidadStock;
DELIMITER //
CREATE FUNCTION fn_VerificarDisponibilidadStock(p_id_producto INT, p_cantidad INT)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_stock INT;
    SELECT stock INTO v_stock FROM productos WHERE id_producto = p_id_producto;
    IF v_stock IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN v_stock >= p_cantidad;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 3. fn_ObtenerPrecioProducto
-- Devuelve el precio de venta actual de un producto.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ObtenerPrecioProducto;
DELIMITER //
CREATE FUNCTION fn_ObtenerPrecioProducto(p_id_producto INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    RETURN (SELECT precio FROM productos WHERE id_producto = p_id_producto);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 4. fn_CalcularEdadCliente
-- Calcula la edad actual de un cliente a partir de su fecha de
-- nacimiento. Devuelve NULL si el cliente no tiene fecha registrada.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularEdadCliente;
DELIMITER //
CREATE FUNCTION fn_CalcularEdadCliente(p_id_cliente INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_fecha_nacimiento DATE;
    SELECT fecha_nacimiento INTO v_fecha_nacimiento
      FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_fecha_nacimiento IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN TIMESTAMPDIFF(YEAR, v_fecha_nacimiento, CURDATE());
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 5. fn_FormatearNombreCompleto
-- Devuelve "Nombre Apellido" con la primera letra de cada palabra en
-- mayuscula, sin importar como se guardo originalmente.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_FormatearNombreCompleto;
DELIMITER //
CREATE FUNCTION fn_FormatearNombreCompleto(p_id_cliente INT)
RETURNS VARCHAR(200)
READS SQL DATA
BEGIN
    DECLARE v_nombre VARCHAR(80);
    DECLARE v_apellido VARCHAR(80);
    SELECT nombre, apellido INTO v_nombre, v_apellido
      FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_nombre IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN CONCAT(
        UPPER(LEFT(v_nombre, 1)), LOWER(SUBSTRING(v_nombre, 2)), ' ',
        UPPER(LEFT(v_apellido, 1)), LOWER(SUBSTRING(v_apellido, 2))
    );
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 6. fn_EsClienteNuevo
-- Devuelve TRUE si la primera compra del cliente fue en los ultimos
-- 30 dias.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_EsClienteNuevo;
DELIMITER //
CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_primera_compra DATETIME;
    SELECT MIN(fecha_venta) INTO v_primera_compra
      FROM ventas
     WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado';
    IF v_primera_compra IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN DATEDIFF(NOW(), v_primera_compra) <= 30;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 7. fn_CalcularCostoEnvio
-- Calcula el costo de envio de una venta segun el peso total de los
-- productos incluidos (tarifa base + costo por kg).
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularCostoEnvio;
DELIMITER //
CREATE FUNCTION fn_CalcularCostoEnvio(p_id_venta INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_peso_total DECIMAL(10,2);
    DECLARE v_tarifa_base DECIMAL(10,2) DEFAULT 8000.00;
    DECLARE v_costo_por_kg DECIMAL(10,2) DEFAULT 3000.00;

    SELECT COALESCE(SUM(p.peso_kg * d.cantidad), 0) INTO v_peso_total
      FROM detalle_ventas d
      JOIN productos p ON p.id_producto = d.id_producto
     WHERE d.id_venta = p_id_venta;

    RETURN ROUND(v_tarifa_base + (v_peso_total * v_costo_por_kg), 2);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 8. fn_AplicarDescuento
-- Aplica un porcentaje de descuento a un monto dado.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_AplicarDescuento;
DELIMITER //
CREATE FUNCTION fn_AplicarDescuento(p_monto DECIMAL(14,2), p_porcentaje DECIMAL(5,2))
RETURNS DECIMAL(14,2)
DETERMINISTIC
NO SQL
BEGIN
    IF p_porcentaje < 0 OR p_porcentaje > 100 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El porcentaje de descuento debe estar entre 0 y 100';
    END IF;
    RETURN ROUND(p_monto - (p_monto * p_porcentaje / 100), 2);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 9. fn_ObtenerUltimaFechaCompra
-- Devuelve la fecha de la ultima compra (no cancelada) de un cliente.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ObtenerUltimaFechaCompra;
DELIMITER //
CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT)
RETURNS DATETIME
READS SQL DATA
BEGIN
    RETURN (
        SELECT MAX(fecha_venta) FROM ventas
         WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado'
    );
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 10. fn_ValidarFormatoEmail
-- Comprueba si una cadena tiene formato de correo electronico valido.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ValidarFormatoEmail;
DELIMITER //
CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(150))
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
    RETURN p_email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$';
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 11. fn_ObtenerNombreCategoria
-- Devuelve el nombre de la categoria a la que pertenece un producto.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ObtenerNombreCategoria;
DELIMITER //
CREATE FUNCTION fn_ObtenerNombreCategoria(p_id_producto INT)
RETURNS VARCHAR(100)
READS SQL DATA
BEGIN
    RETURN (
        SELECT c.nombre
          FROM productos p
          JOIN categorias c ON c.id_categoria = p.id_categoria
         WHERE p.id_producto = p_id_producto
    );
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 12. fn_ContarVentasCliente
-- Cuenta el numero total de compras (no canceladas) de un cliente.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ContarVentasCliente;
DELIMITER //
CREATE FUNCTION fn_ContarVentasCliente(p_id_cliente INT)
RETURNS INT
READS SQL DATA
BEGIN
    RETURN (
        SELECT COUNT(*) FROM ventas
         WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado'
    );
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 13. fn_CalcularDiasDesdeUltimaCompra
-- Devuelve el numero de dias transcurridos desde la ultima compra de
-- un cliente. NULL si nunca ha comprado.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularDiasDesdeUltimaCompra;
DELIMITER //
CREATE FUNCTION fn_CalcularDiasDesdeUltimaCompra(p_id_cliente INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_ultima DATETIME;
    SET v_ultima = (
        SELECT MAX(fecha_venta) FROM ventas
         WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado'
    );
    IF v_ultima IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN DATEDIFF(NOW(), v_ultima);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 14. fn_DeterminarEstadoLealtad
-- Asigna un nivel de lealtad (Bronce/Plata/Oro) segun el gasto total
-- historico del cliente. Los mismos umbrales que usa el seed de datos
-- y que los triggers de 05_Triggers.sql mantendran actualizados.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_DeterminarEstadoLealtad;
DELIMITER //
CREATE FUNCTION fn_DeterminarEstadoLealtad(p_id_cliente INT)
RETURNS VARCHAR(10)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(14,2);
    SET v_total = (
        SELECT COALESCE(SUM(total), 0) FROM ventas
         WHERE id_cliente = p_id_cliente AND estado <> 'Cancelado'
    );
    IF v_total >= 700000 THEN
        RETURN 'Oro';
    ELSEIF v_total >= 300000 THEN
        RETURN 'Plata';
    ELSE
        RETURN 'Bronce';
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 15. fn_GenerarSKU
-- Genera un SKU a partir del nombre del producto y su categoria,
-- usando un consecutivo dentro de la categoria.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_GenerarSKU;
DELIMITER //
CREATE FUNCTION fn_GenerarSKU(p_nombre VARCHAR(150), p_id_categoria INT)
RETURNS VARCHAR(50)
READS SQL DATA
BEGIN
    DECLARE v_prefijo_categoria VARCHAR(10);
    DECLARE v_prefijo_nombre VARCHAR(10);
    DECLARE v_consecutivo INT;

    SELECT UPPER(LEFT(REPLACE(nombre, ' ', ''), 4)) INTO v_prefijo_categoria
      FROM categorias WHERE id_categoria = p_id_categoria;

    SET v_prefijo_nombre = UPPER(LEFT(REPLACE(p_nombre, ' ', ''), 4));

    SELECT COUNT(*) + 1 INTO v_consecutivo
      FROM productos WHERE id_categoria = p_id_categoria;

    RETURN CONCAT('SKU-', COALESCE(v_prefijo_categoria, 'GEN'), '-',
                  v_prefijo_nombre, '-', LPAD(v_consecutivo, 3, '0'));
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 16. fn_CalcularIVA
-- Calcula el IVA (19%, tarifa general en Colombia) sobre el total de
-- una venta.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_CalcularIVA;
DELIMITER //
CREATE FUNCTION fn_CalcularIVA(p_id_venta INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(14,2);
    DECLARE v_tasa_iva DECIMAL(5,4) DEFAULT 0.19;
    SELECT total INTO v_total FROM ventas WHERE id_venta = p_id_venta;
    IF v_total IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN ROUND(v_total * v_tasa_iva, 2);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 17. fn_ObtenerStockTotalPorCategoria
-- Suma el stock de todos los productos activos de una categoria.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ObtenerStockTotalPorCategoria;
DELIMITER //
CREATE FUNCTION fn_ObtenerStockTotalPorCategoria(p_id_categoria INT)
RETURNS INT
READS SQL DATA
BEGIN
    RETURN (
        SELECT COALESCE(SUM(stock), 0) FROM productos
         WHERE id_categoria = p_id_categoria AND activo = TRUE
    );
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 18. fn_EstimarFechaEntrega
-- Calcula la fecha estimada de entrega de un pedido segun la ciudad
-- del cliente: 3 dias habiles si hay sucursal fisica en su ciudad,
-- 7 dias habiles en caso contrario.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_EstimarFechaEntrega;
DELIMITER //
CREATE FUNCTION fn_EstimarFechaEntrega(p_id_cliente INT)
RETURNS DATE
READS SQL DATA
BEGIN
    DECLARE v_ciudad VARCHAR(100);
    DECLARE v_tiene_sucursal INT;

    SELECT ciudad INTO v_ciudad FROM clientes WHERE id_cliente = p_id_cliente;
    IF v_ciudad IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT COUNT(*) INTO v_tiene_sucursal FROM sucursales WHERE ciudad = v_ciudad;

    IF v_tiene_sucursal > 0 THEN
        RETURN DATE_ADD(CURDATE(), INTERVAL 3 DAY);
    ELSE
        RETURN DATE_ADD(CURDATE(), INTERVAL 7 DAY);
    END IF;
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 19. fn_ConvertirMoneda
-- Convierte un monto a otra moneda usando una tasa de cambio fija
-- suministrada por el llamador (ej. COP a USD).
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ConvertirMoneda;
DELIMITER //
CREATE FUNCTION fn_ConvertirMoneda(p_monto DECIMAL(14,2), p_tasa_cambio DECIMAL(14,6))
RETURNS DECIMAL(14,2)
DETERMINISTIC
NO SQL
BEGIN
    IF p_tasa_cambio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La tasa de cambio debe ser mayor que cero';
    END IF;
    RETURN ROUND(p_monto * p_tasa_cambio, 2);
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- 20. fn_ValidarComplejidadContrasena
-- Verifica que una contrasena cumpla: longitud minima de 8, al menos
-- una mayuscula, una minuscula, un digito y un caracter especial.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_ValidarComplejidadContrasena;
DELIMITER //
CREATE FUNCTION fn_ValidarComplejidadContrasena(p_contrasena VARCHAR(255))
RETURNS BOOLEAN
DETERMINISTIC
NO SQL
BEGIN
    RETURN (
        CHAR_LENGTH(p_contrasena) >= 8
        AND p_contrasena REGEXP '[A-Z]'
        AND p_contrasena REGEXP '[a-z]'
        AND p_contrasena REGEXP '[0-9]'
        AND p_contrasena REGEXP '[^A-Za-z0-9]'
    );
END//
DELIMITER ;