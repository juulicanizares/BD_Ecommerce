-- =====================================================================
-- 04_Seguridad.sql
-- =====================================================================

USE ecommerce_db;

-- ---------------------------------------------------------------------
-- Bootstrap: tabla de auditoria de precios (definicion final y
-- autoritativa en 05_Triggers.sql; aqui solo se garantiza que exista
-- para poder otorgar privilegios sobre ella).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS log_cambios_precio (
    id_log          INT AUTO_INCREMENT PRIMARY KEY,
    id_producto     INT NULL,
    precio_anterior DECIMAL(12,2) NOT NULL,
    precio_nuevo    DECIMAL(12,2) NOT NULL,
    usuario_bd      VARCHAR(100) NOT NULL,
    fecha_cambio    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_log_precio_producto FOREIGN KEY (id_producto)
        REFERENCES productos (id_producto) ON DELETE SET NULL
) ENGINE = InnoDB COMMENT = 'Auditoria de cambios de precio (ver 05_Triggers.sql)';

-- =====================================================================
-- REQUISITOS 1-6: ROLES
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Administrador_Sistema: control total sobre la base de datos.
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Administrador_Sistema';
CREATE ROLE 'Administrador_Sistema';
GRANT ALL PRIVILEGES ON ecommerce_db.* TO 'Administrador_Sistema';

-- ---------------------------------------------------------------------
-- 2. Gerente_Marketing: solo lectura sobre ventas y clientes.
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Gerente_Marketing';
CREATE ROLE 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.ventas   TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.clientes TO 'Gerente_Marketing';

-- ---------------------------------------------------------------------
-- 3. Analista_Datos: solo lectura a todas las tablas, excepto las de
-- auditoria (log_*, alertas_stock, ventas_archivadas,
-- reporte_ventas_semanales, que se crean en 05/06 y nunca se listan
-- aqui explicitamente).
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Analista_Datos';
CREATE ROLE 'Analista_Datos';
GRANT SELECT ON ecommerce_db.categorias      TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.proveedores     TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.sucursales      TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.productos       TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.clientes        TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.ventas          TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.detalle_ventas  TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.promociones     TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.carritos        TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.carrito_items   TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.producto_vistas TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.resenas         TO 'Analista_Datos';

-- ---------------------------------------------------------------------
-- 4. Empleado_Inventario: solo puede modificar productos (stock y
-- ubicacion). 
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Empleado_Inventario';
CREATE ROLE 'Empleado_Inventario';
GRANT SELECT ON ecommerce_db.productos TO 'Empleado_Inventario';
GRANT UPDATE (stock, ubicacion_almacen) ON ecommerce_db.productos TO 'Empleado_Inventario';

-- ---------------------------------------------------------------------
-- 5. Atencion_Cliente: puede ver clientes (via vista sin datos
-- sensibles, requisito #13) y ventas, y cambiar el estado de un
-- pedido, pero no puede modificar precios (no recibe ningun privilegio
-- de escritura sobre productos).
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Atencion_Cliente';
CREATE ROLE 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.ventas             TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.detalle_ventas     TO 'Atencion_Cliente';
GRANT UPDATE (estado) ON ecommerce_db.ventas    TO 'Atencion_Cliente';
-- El SELECT sobre datos de clientes se otorga mas abajo, sobre la
-- vista v_info_clientes_basica (requisito 13), no sobre la tabla.

-- ---------------------------------------------------------------------
-- 6. Auditor_Financiero: solo lectura a ventas, productos y logs de
-- precios.
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Auditor_Financiero';
CREATE ROLE 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.ventas             TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.productos          TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.log_cambios_precio TO 'Auditor_Financiero';

-- ---------------------------------------------------------------------
-- 17. Visitante: solo puede ver la tabla productos (publico general /
-- catalogo sin autenticacion completa).
-- ---------------------------------------------------------------------
DROP ROLE IF EXISTS 'Visitante';
CREATE ROLE 'Visitante';
GRANT SELECT ON ecommerce_db.productos TO 'Visitante';

-- =====================================================================
-- REQUISITOS 7-10: USUARIOS Y ASIGNACION DE ROLES
-- =====================================================================

DROP USER IF EXISTS 'admin_user'@'localhost';
CREATE USER 'admin_user'@'localhost' IDENTIFIED BY 'Adm1n$2024Secure!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
GRANT 'Administrador_Sistema' TO 'admin_user'@'localhost';
SET DEFAULT ROLE 'Administrador_Sistema' TO 'admin_user'@'localhost';

DROP USER IF EXISTS 'marketing_user'@'%';
CREATE USER 'marketing_user'@'%' IDENTIFIED BY 'Mkt2024$Secure!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
GRANT 'Gerente_Marketing' TO 'marketing_user'@'%';
SET DEFAULT ROLE 'Gerente_Marketing' TO 'marketing_user'@'%';

DROP USER IF EXISTS 'inventory_user'@'%';
CREATE USER 'inventory_user'@'%' IDENTIFIED BY 'Inv2024$Secure!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
GRANT 'Empleado_Inventario' TO 'inventory_user'@'%';
SET DEFAULT ROLE 'Empleado_Inventario' TO 'inventory_user'@'%';

DROP USER IF EXISTS 'support_user'@'%';
CREATE USER 'support_user'@'%' IDENTIFIED BY 'Sup2024$Secure!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
GRANT 'Atencion_Cliente' TO 'support_user'@'%';
SET DEFAULT ROLE 'Atencion_Cliente' TO 'support_user'@'%';

-- Usuarios adicionales de demostracion para los roles restantes
-- (no exigidos explicitamente en los requisitos 7-10, pero necesarios
-- para poder probar Analista_Datos, Auditor_Financiero y Visitante).
DROP USER IF EXISTS 'analyst_user'@'%';
CREATE USER 'analyst_user'@'%' IDENTIFIED BY 'Ana2024$Secure!'
    WITH MAX_QUERIES_PER_HOUR 500               -- ver requisito 18
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
GRANT 'Analista_Datos' TO 'analyst_user'@'%';
SET DEFAULT ROLE 'Analista_Datos' TO 'analyst_user'@'%';

DROP USER IF EXISTS 'auditor_user'@'%';
CREATE USER 'auditor_user'@'%' IDENTIFIED BY 'Aud2024$Secure!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
GRANT 'Auditor_Financiero' TO 'auditor_user'@'%';
SET DEFAULT ROLE 'Auditor_Financiero' TO 'auditor_user'@'%';

DROP USER IF EXISTS 'visitor_user'@'%';
CREATE USER 'visitor_user'@'%' IDENTIFIED BY 'Vis2024$Secure!'
    PASSWORD EXPIRE INTERVAL 90 DAY;
GRANT 'Visitante' TO 'visitor_user'@'%';
SET DEFAULT ROLE 'Visitante' TO 'visitor_user'@'%';

-- Activa automaticamente los roles por defecto de cada usuario al
-- conectarse, sin necesidad de ejecutar SET ROLE manualmente.
SET GLOBAL activate_all_roles_on_login = ON;

-- =====================================================================
-- 11. Impedir que Analista_Datos ejecute DELETE o TRUNCATE
-- =====================================================================

-- =====================================================================
-- 12. (Ver nota de cabecera del archivo). 
-- =====================================================================

-- =====================================================================
-- 13. Vista v_info_clientes_basica: oculta datos sensibles (hash de
-- contrasena y direccion de envio) y se otorga a Atencion_Cliente.
-- =====================================================================
DROP VIEW IF EXISTS v_info_clientes_basica;
CREATE VIEW v_info_clientes_basica AS
SELECT
    id_cliente,
    nombre,
    apellido,
    email,
    ciudad,
    region,
    nivel_lealtad,
    fecha_registro
FROM clientes;

GRANT SELECT ON ecommerce_db.v_info_clientes_basica TO 'Atencion_Cliente';

-- =====================================================================
-- 14. Revocar UPDATE sobre la columna precio de productos al rol

-- =====================================================================

-- =====================================================================
-- 15. Politica de contrasenas seguras
-- =====================================================================


SET GLOBAL validate_password.policy             = 'STRONG';
SET GLOBAL validate_password.length             = 10;
SET GLOBAL validate_password.mixed_case_count   = 1;
SET GLOBAL validate_password.number_count       = 1;
SET GLOBAL validate_password.special_char_count = 1;

ALTER USER 'admin_user'@'localhost'   PASSWORD HISTORY 5 PASSWORD REUSE INTERVAL 365 DAY;
ALTER USER 'marketing_user'@'%'       PASSWORD HISTORY 5 PASSWORD REUSE INTERVAL 365 DAY;
ALTER USER 'inventory_user'@'%'       PASSWORD HISTORY 5 PASSWORD REUSE INTERVAL 365 DAY;
ALTER USER 'support_user'@'%'         PASSWORD HISTORY 5 PASSWORD REUSE INTERVAL 365 DAY;
ALTER USER 'analyst_user'@'%'         PASSWORD HISTORY 5 PASSWORD REUSE INTERVAL 365 DAY;
ALTER USER 'auditor_user'@'%'         PASSWORD HISTORY 5 PASSWORD REUSE INTERVAL 365 DAY;

-- =====================================================================
-- 16. Asegurar que 'root' no pueda usarse desde conexiones remotas
-- =====================================================================
DROP USER IF EXISTS 'root'@'%';
-- Verificacion sugerida tras ejecutar este script:
-- SELECT user, host FROM mysql.user WHERE user = 'root';
-- Debe devolver unicamente la fila ('root','localhost').

-- =====================================================================
-- 18. Limitar consultas por hora para Analista_Datos

-- =====================================================================
-- 19. Acceso a ventas restringido por sucursal del usuario
-- =====================================================================
CREATE TABLE IF NOT EXISTS usuarios_sucursal (
    usuario_bd  VARCHAR(100) PRIMARY KEY,
    id_sucursal INT NOT NULL,
    CONSTRAINT fk_usuario_sucursal FOREIGN KEY (id_sucursal)
        REFERENCES sucursales (id_sucursal) ON DELETE CASCADE
) ENGINE = InnoDB COMMENT = 'Mapeo de cuentas de BD a su sucursal, para la vista de seguridad por fila';

INSERT INTO usuarios_sucursal (usuario_bd, id_sucursal) VALUES
('support_user', 1),
('inventory_user', 2)
ON DUPLICATE KEY UPDATE id_sucursal = VALUES(id_sucursal);

DROP VIEW IF EXISTS v_ventas_por_sucursal_usuario;
CREATE SQL SECURITY DEFINER VIEW v_ventas_por_sucursal_usuario AS
SELECT v.*
FROM ventas v
JOIN usuarios_sucursal us
  ON us.usuario_bd = SUBSTRING_INDEX(USER(), '@', 1)
WHERE v.id_sucursal = us.id_sucursal;

DROP ROLE IF EXISTS 'Personal_Sucursal';
CREATE ROLE 'Personal_Sucursal';
GRANT SELECT ON ecommerce_db.v_ventas_por_sucursal_usuario TO 'Personal_Sucursal';
-- Un usuario de sucursal recibiria este rol EN LUGAR DE acceso directo
-- a la tabla ventas, por ejemplo:
-- GRANT 'Personal_Sucursal' TO 'support_user'@'%';

-- =====================================================================
-- 20. Auditar todos los intentos de inicio de sesion fallidos
-- =====================================================================
DELIMITER //

CREATE PROCEDURE sp_instalar_connection_control()
BEGIN
    -- Capturar el error 1125 (plugin ya existe) para que no detenga el script
    DECLARE CONTINUE HANDLER FOR 1125 BEGIN END;

    INSTALL PLUGIN CONNECTION_CONTROL SONAME 'connection_control.dll';
    INSTALL PLUGIN CONNECTION_CONTROL_FAILED_LOGIN_ATTEMPTS SONAME 'connection_control.dll';
END //

DELIMITER ;

-- Ejecutar e inmediatamente limpiar el procedimiento
CALL sp_instalar_connection_control();
DROP PROCEDURE IF EXISTS sp_instalar_connection_control;