USE ecommerce_db;
/*usar la base de datos*/

SET GLOBAL event_scheduler = ON;
/*el planificador de eventos activado*/

ALTER TABLE clientes 
ADD COLUMN fecha_ultima_compra = ultima_fecha_compra;
/*añadir ultima  compra a la tabla clientes*/

ALTER TABLE clientes 
ADD COLUMN  actividad_cliente = ultima_fecha_compra;
/*añadir la actividad a la tabla clientes*/

DROP TRIGGER IF EXISTS trg_actualizada_ultima_fecha_compra;
DELIMITER //
CREATE TRIGGER trg_actualizada_ultima_fecha_compra
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    UPDATE clientes
       SET ultima_fecha_compra = NEW.fecha_venta
     WHERE id_cliente = NEW.id_cliente;
END//
DELIMITER ;
/*para actualizar la ultima fecha de compra en la tabla clientes 
 * y el id del cliente para que sea el mismo*/


DROP EVENT IF EXISTS evt_desactivar_cuentas_inactivas;
DELIMITER //
CREATE EVENT evt_desactivar_cuentas_inactivas
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    UPDATE clientes
       SET activo = FALSE
     WHERE ultima_fecha_compra < DATE_SUB(NOW(), INTERVAL 2 YEAR)
        OR (ultima_fecha_compra IS NULL AND fecha_registro < DATE_SUB(NOW(), INTERVAL 2 YEAR));
END//
DELIMITER ;

/*desactivar la cuentas inactivas que lo haga 1 vez al mes en la tabla clientes 
 * para los que no cumplen es decir los activos un booleano false
 * porque si cumplen y ques esto sea en un intervalo de 2 años*/
