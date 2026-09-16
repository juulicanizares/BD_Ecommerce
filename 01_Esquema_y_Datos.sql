-- =====================================================================
-- 01_Esquema_y_Datos.sql
-- =====================================================================

DROP DATABASE IF EXISTS ecommerce_db;
CREATE DATABASE ecommerce_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE ecommerce_db;

-- =====================================================================
-- SECCION 1: TABLAS MAESTRAS (sin dependencias externas)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tabla: categorias
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS categorias;
CREATE TABLE categorias (
    id_categoria      INT AUTO_INCREMENT PRIMARY KEY,
    nombre            VARCHAR(100) NOT NULL,
    descripcion       TEXT,
    contador_productos INT NOT NULL DEFAULT 0,
    CONSTRAINT uq_categoria_nombre UNIQUE (nombre)
) ENGINE = InnoDB COMMENT = 'Categorias de clasificacion de productos';

-- ---------------------------------------------------------------------
-- Tabla: proveedores
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS proveedores;
CREATE TABLE proveedores (
    id_proveedor      INT AUTO_INCREMENT PRIMARY KEY,
    nombre            VARCHAR(150) NOT NULL,
    email_contacto    VARCHAR(150),
    telefono_contacto VARCHAR(30),
    CONSTRAINT uq_proveedor_email UNIQUE (email_contacto)
) ENGINE = InnoDB COMMENT = 'Proveedores que suministran productos';

-- ---------------------------------------------------------------------
-- Tabla: sucursales
-- (Soporta el requisito de seguridad #19: ventas visibles solo para la
--  sucursal del usuario, y el analisis geografico de ventas)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS sucursales;
CREATE TABLE sucursales (
    id_sucursal INT AUTO_INCREMENT PRIMARY KEY,
    nombre      VARCHAR(100) NOT NULL,
    ciudad      VARCHAR(100) NOT NULL,
    direccion   VARCHAR(200)
) ENGINE = InnoDB COMMENT = 'Sucursales fisicas de la tienda';

-- =====================================================================
-- SECCION 2: PRODUCTOS (depende de categorias y proveedores)
-- =====================================================================

DROP TABLE IF EXISTS productos;
CREATE TABLE productos (
    id_producto        INT AUTO_INCREMENT PRIMARY KEY,
    nombre             VARCHAR(150) NOT NULL,
    descripcion        TEXT,
    precio             DECIMAL(12,2) NOT NULL,
    costo              DECIMAL(12,2) NOT NULL,
    stock              INT NOT NULL DEFAULT 0,
    stock_minimo       INT NOT NULL DEFAULT 10,
    sku                VARCHAR(50) NOT NULL,
    peso_kg            DECIMAL(8,2) NOT NULL DEFAULT 0.50,
    ubicacion_almacen  VARCHAR(30),
    id_categoria       INT NOT NULL,
    id_proveedor       INT NOT NULL,
    fecha_creacion     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                        ON UPDATE CURRENT_TIMESTAMP,
    activo             BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_producto_nombre UNIQUE (nombre),
    CONSTRAINT uq_producto_sku UNIQUE (sku),
    CONSTRAINT chk_producto_precio CHECK (precio > 0),
    CONSTRAINT chk_producto_costo CHECK (costo >= 0),
    CONSTRAINT chk_producto_stock CHECK (stock >= 0),
    CONSTRAINT fk_producto_categoria FOREIGN KEY (id_categoria)
        REFERENCES categorias (id_categoria) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_producto_proveedor FOREIGN KEY (id_proveedor)
        REFERENCES proveedores (id_proveedor) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB COMMENT = 'Catalogo de productos';

CREATE INDEX idx_productos_activo ON productos (activo);
CREATE INDEX idx_productos_categoria ON productos (id_categoria);

-- =====================================================================
-- SECCION 3: CLIENTES (depende de sucursales, auto-referencia)
-- =====================================================================

DROP TABLE IF EXISTS clientes;
CREATE TABLE clientes (
    id_cliente        INT AUTO_INCREMENT PRIMARY KEY,
    nombre            VARCHAR(80) NOT NULL,
    apellido          VARCHAR(80) NOT NULL,
    email             VARCHAR(150) NOT NULL,
    contrasena_hash   VARCHAR(255) NOT NULL,
    direccion_envio   VARCHAR(255),
    ciudad            VARCHAR(100),
    region            VARCHAR(100),
    fecha_nacimiento  DATE,
    id_sucursal       INT NULL,
    referido_por      INT NULL,
    total_gastado     DECIMAL(14,2) NOT NULL DEFAULT 0,
    nivel_lealtad     ENUM('Bronce','Plata','Oro') NOT NULL DEFAULT 'Bronce',
    fecha_ultimo_pedido TIMESTAMP NULL,
    fecha_registro    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_cliente_email UNIQUE (email),
    CONSTRAINT fk_cliente_sucursal FOREIGN KEY (id_sucursal)
        REFERENCES sucursales (id_sucursal) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_cliente_referido_por FOREIGN KEY (referido_por)
        REFERENCES clientes (id_cliente) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE = InnoDB COMMENT = 'Clientes registrados';

CREATE INDEX idx_clientes_ciudad ON clientes (ciudad);
CREATE INDEX idx_clientes_fecha_registro ON clientes (fecha_registro);

-- =====================================================================
-- SECCION 4: VENTAS Y DETALLE (relacion N:M via tabla puente)
-- =====================================================================

DROP TABLE IF EXISTS ventas;
CREATE TABLE ventas (
    id_venta    INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente  INT NOT NULL,
    id_sucursal INT NULL,
    fecha_venta TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado      ENUM('Pendiente de Pago','Procesando','Enviado','Entregado','Cancelado')
                NOT NULL DEFAULT 'Pendiente de Pago',
    total       DECIMAL(14,2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_venta_cliente FOREIGN KEY (id_cliente)
        REFERENCES clientes (id_cliente) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_venta_sucursal FOREIGN KEY (id_sucursal)
        REFERENCES sucursales (id_sucursal) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE = InnoDB COMMENT = 'Encabezado de las ventas (ordenes)';

CREATE INDEX idx_ventas_fecha ON ventas (fecha_venta);
CREATE INDEX idx_ventas_estado ON ventas (estado);
CREATE INDEX idx_ventas_cliente ON ventas (id_cliente);

DROP TABLE IF EXISTS detalle_ventas;
CREATE TABLE detalle_ventas (
    id_detalle                INT AUTO_INCREMENT PRIMARY KEY,
    id_venta                  INT NOT NULL,
    id_producto                INT NOT NULL,
    cantidad                   INT NOT NULL,
    precio_unitario_congelado DECIMAL(12,2) NOT NULL,
    CONSTRAINT chk_detalle_cantidad CHECK (cantidad > 0),
    CONSTRAINT chk_detalle_precio CHECK (precio_unitario_congelado > 0),
    CONSTRAINT fk_detalle_venta FOREIGN KEY (id_venta)
        REFERENCES ventas (id_venta) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_detalle_producto FOREIGN KEY (id_producto)
        REFERENCES productos (id_producto) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB COMMENT = 'Lineas de detalle de cada venta (precio historico)';

CREATE INDEX idx_detalle_producto ON detalle_ventas (id_producto);

-- =====================================================================
-- SECCION 5: TABLAS DE APOYO (promociones, carritos, vistas, resenas)
-- =====================================================================

DROP TABLE IF EXISTS promociones;
CREATE TABLE promociones (
    id_promocion         INT AUTO_INCREMENT PRIMARY KEY,
    id_producto          INT NOT NULL,
    porcentaje_descuento DECIMAL(5,2) NOT NULL,
    fecha_inicio         DATETIME NOT NULL,
    fecha_fin            DATETIME NOT NULL,
    activo               BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_promo_porcentaje CHECK (porcentaje_descuento BETWEEN 0 AND 100),
    CONSTRAINT chk_promo_fechas CHECK (fecha_fin >= fecha_inicio),
    CONSTRAINT fk_promocion_producto FOREIGN KEY (id_producto)
        REFERENCES productos (id_producto) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB COMMENT = 'Promociones/descuentos temporales por producto';

DROP TABLE IF EXISTS carritos;
CREATE TABLE carritos (
    id_carrito         INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente         INT NOT NULL,
    fecha_creacion     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                         ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_carrito_cliente FOREIGN KEY (id_cliente)
        REFERENCES clientes (id_cliente) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB COMMENT = 'Carritos de compra (para analisis de abandono)';

DROP TABLE IF EXISTS carrito_items;
CREATE TABLE carrito_items (
    id_item        INT AUTO_INCREMENT PRIMARY KEY,
    id_carrito     INT NOT NULL,
    id_producto    INT NOT NULL,
    cantidad       INT NOT NULL DEFAULT 1,
    fecha_agregado TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_carrito_item_cantidad CHECK (cantidad > 0),
    CONSTRAINT fk_carrito_item_carrito FOREIGN KEY (id_carrito)
        REFERENCES carritos (id_carrito) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_carrito_item_producto FOREIGN KEY (id_producto)
        REFERENCES productos (id_producto) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB COMMENT = 'Items dentro de cada carrito de compra';

DROP TABLE IF EXISTS producto_vistas;
CREATE TABLE producto_vistas (
    id_vista    INT AUTO_INCREMENT PRIMARY KEY,
    id_producto INT NOT NULL,
    id_cliente  INT NULL,
    fecha_vista TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_vista_producto FOREIGN KEY (id_producto)
        REFERENCES productos (id_producto) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_vista_cliente FOREIGN KEY (id_cliente)
        REFERENCES clientes (id_cliente) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE = InnoDB COMMENT = 'Registro de visualizaciones de producto (vistas vs compras)';

CREATE INDEX idx_vistas_producto ON producto_vistas (id_producto);

DROP TABLE IF EXISTS resenas;
CREATE TABLE resenas (
    id_resena    INT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    id_cliente   INT NOT NULL,
    calificacion TINYINT NOT NULL,
    comentario   TEXT,
    fecha_resena TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_resena_calificacion CHECK (calificacion BETWEEN 1 AND 5),
    CONSTRAINT fk_resena_producto FOREIGN KEY (id_producto)
        REFERENCES productos (id_producto) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_resena_cliente FOREIGN KEY (id_cliente)
        REFERENCES clientes (id_cliente) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE = InnoDB COMMENT = 'Resenas de clientes sobre productos comprados';

-- =====================================================================
-- SECCION 6: DATOS DE EJEMPLO
-- =====================================================================

-- ---------------------------------------------------------------------
-- categorias
-- ---------------------------------------------------------------------
INSERT INTO categorias (nombre, descripcion) VALUES
('Electrónica', 'Dispositivos electrónicos y accesorios tecnológicos'),
('Ropa y Moda', 'Prendas de vestir y accesorios de moda'),
('Hogar y Cocina', 'Artículos para el hogar y la cocina'),
('Deportes', 'Equipamiento y accesorios deportivos'),
('Juguetes', 'Juguetes y juegos para todas las edades'),
('Libros', 'Libros de ficción, no ficción y educativos'),
('Belleza y Cuidado Personal', 'Productos de cuidado personal y belleza'),
('Mascotas', 'Accesorios y productos para mascotas');

-- ---------------------------------------------------------------------
-- proveedores
-- ---------------------------------------------------------------------
INSERT INTO proveedores (nombre, email_contacto, telefono_contacto) VALUES
('TechGlobal Supplies', 'contacto@techglobal.com', '6017001100'),
('Moda Andina S.A.S.', 'ventas@modaandina.com', '6014455200'),
('Hogar Confort Ltda.', 'info@hogarconfort.com', '6013322100'),
('DeportesXtreme', 'contacto@deportesxtreme.com', '6018877600'),
('Editorial Horizonte', 'pedidos@editorialhorizonte.com', '6015566300'),
('PetCare Import', 'contacto@petcareimport.com', '6019988400');

-- ---------------------------------------------------------------------
-- sucursales
-- ---------------------------------------------------------------------
INSERT INTO sucursales (nombre, ciudad, direccion) VALUES
('Sucursal Bogotá Centro', 'Bogotá', 'Cra 7 # 24-15'),
('Sucursal Medellín Poblado', 'Medellín', 'Cra 43A # 10-20'),
('Sucursal Bucaramanga Cabecera', 'Bucaramanga', 'Cra 33 # 45-10');

-- ---------------------------------------------------------------------
-- productos (24 registros, 3 por debajo de stock_minimo para pruebas)
-- ---------------------------------------------------------------------
INSERT INTO productos
(nombre, descripcion, precio, costo, stock, stock_minimo, sku, peso_kg, ubicacion_almacen, id_categoria, id_proveedor) VALUES
('Audífonos Bluetooth ProSound X200', 'Audífonos inalámbricos con cancelación de ruido', 189000, 110000, 85, 15, 'SKU-ELEC-001', 0.25, 'A1-01', 1, 1),
('Smartwatch FitPulse 5', 'Reloj inteligente con monitoreo de salud', 349000, 210000, 40, 10, 'SKU-ELEC-002', 0.15, 'A1-02', 1, 1),
('Parlante Portátil BoomBox Mini', 'Parlante Bluetooth resistente al agua', 129000, 75000, 120, 20, 'SKU-ELEC-003', 0.60, 'A1-03', 1, 1),
('Cargador Rápido USB-C 65W', 'Cargador de pared con carga rápida', 59000, 28000, 200, 30, 'SKU-ELEC-004', 0.10, 'A1-04', 1, 1),
('Cámara de Seguridad WiFi 1080p', 'Cámara IP para monitoreo del hogar', 219000, 130000, 55, 10, 'SKU-ELEC-005', 0.30, 'A1-05', 1, 1),
('Chaqueta Impermeable Urban', 'Chaqueta unisex resistente al agua', 159000, 90000, 60, 10, 'SKU-ROPA-001', 0.50, 'B2-01', 2, 2),
('Jean Slim Fit Azul Oscuro', 'Jean de mezclilla corte slim', 99000, 52000, 95, 15, 'SKU-ROPA-002', 0.40, 'B2-02', 2, 2),
('Camiseta Básica Algodón', 'Camiseta 100% algodón, varios colores', 39000, 18000, 300, 40, 'SKU-ROPA-003', 0.20, 'B2-03', 2, 2),
('Zapatillas Urbanas Runner', 'Zapatillas deportivas para uso diario', 219000, 130000, 70, 12, 'SKU-ROPA-004', 0.90, 'B2-04', 2, 2),
('Bufanda Tejida Invierno', 'Bufanda de lana tejida a mano', 45000, 20000, 5, 10, 'SKU-ROPA-005', 0.15, 'B2-05', 2, 2),
('Juego de Ollas Antiadherentes x5', 'Set de ollas con recubrimiento antiadherente', 289000, 170000, 35, 8, 'SKU-HOGA-001', 4.20, 'C3-01', 3, 3),
('Licuadora Multifunción 900W', 'Licuadora de alto rendimiento', 175000, 100000, 48, 10, 'SKU-HOGA-002', 2.50, 'C3-02', 3, 3),
('Set de Toallas Premium x6', 'Toallas de algodón egipcio', 89000, 45000, 80, 15, 'SKU-HOGA-003', 1.80, 'C3-03', 3, 3),
('Lámpara de Mesa LED Regulable', 'Lámpara con control de intensidad', 65000, 32000, 3, 10, 'SKU-HOGA-004', 0.80, 'C3-04', 3, 3),
('Balón de Fútbol Profesional', 'Balón de competición talla 5', 89000, 45000, 65, 15, 'SKU-DEPO-001', 0.45, 'D4-01', 4, 4),
('Set de Mancuernas Ajustables 20kg', 'Mancuernas ajustables para entrenamiento en casa', 249000, 150000, 25, 8, 'SKU-DEPO-002', 20.00, 'D4-02', 4, 4),
('Colchoneta de Yoga Antideslizante', 'Colchoneta ecológica de 6mm', 55000, 25000, 150, 25, 'SKU-DEPO-003', 1.10, 'D4-03', 4, 4),
('Bicicleta Estática Plegable', 'Bicicleta para cardio con pantalla LCD', 899000, 560000, 12, 5, 'SKU-DEPO-004', 30.00, 'D4-04', 4, 4),
('Rompecabezas 1000 Piezas Paisaje', 'Rompecabezas de paisaje natural', 45000, 20000, 90, 15, 'SKU-JUGU-001', 0.60, 'E5-01', 5, 1),
('Set de Bloques de Construcción', 'Bloques compatibles para armar', 129000, 70000, 50, 10, 'SKU-JUGU-002', 1.20, 'E5-02', 5, 1),
('Novela "El Eco del Silencio"', 'Novela de ficción contemporánea', 55000, 25000, 130, 20, 'SKU-LIBR-001', 0.35, 'F6-01', 6, 5),
('Libro de Cocina Internacional', 'Recetas de cocina de todo el mundo', 79000, 38000, 60, 12, 'SKU-LIBR-002', 0.70, 'F6-02', 6, 5),
('Set de Skincare Facial Hidratante', 'Kit de limpieza e hidratación facial', 135000, 70000, 2, 10, 'SKU-BELL-001', 0.30, 'G7-01', 7, 3),
('Correa y Arnés para Perro Talla M', 'Set de correa y arnés ajustable', 49000, 22000, 75, 15, 'SKU-MASC-001', 0.25, 'H8-01', 8, 6);

-- ---------------------------------------------------------------------
-- clientes (15 registros)
-- ---------------------------------------------------------------------
INSERT INTO clientes
(nombre, apellido, email, contrasena_hash, direccion_envio, ciudad, region, fecha_nacimiento, id_sucursal, referido_por, fecha_registro) VALUES
('Andrea', 'Restrepo', 'andrea.restrepo@example.com', SHA2('ClienteDemo#01', 256), 'Calle 80 # 12-34', 'Bogotá', 'Cundinamarca', '1990-04-12', 1, NULL, '2024-01-15 10:00:00'),
('Camilo', 'Torres', 'camilo.torres@example.com', SHA2('ClienteDemo#02', 256), 'Cra 15 # 45-10', 'Bogotá', 'Cundinamarca', '1985-09-03', 1, NULL, '2024-01-22 11:30:00'),
('Laura', 'Jiménez', 'laura.jimenez@example.com', SHA2('ClienteDemo#03', 256), 'Cra 43 # 20-15', 'Medellín', 'Antioquia', '1995-12-20', 2, NULL, '2024-02-10 09:15:00'),
('Sebastián', 'Gómez', 'sebastian.gomez@example.com', SHA2('ClienteDemo#04', 256), 'Calle 33 # 70-40', 'Medellín', 'Antioquia', '1988-06-30', 2, 3, '2024-02-18 14:45:00'),
('Valentina', 'Ruiz', 'valentina.ruiz@example.com', SHA2('ClienteDemo#05', 256), 'Cra 27 # 50-12', 'Bucaramanga', 'Santander', '1999-01-08', 3, NULL, '2024-03-05 08:20:00'),
('Julián', 'Herrera', 'julian.herrera@example.com', SHA2('ClienteDemo#06', 256), 'Calle 56 # 22-08', 'Bucaramanga', 'Santander', '1979-11-11', 3, 5, '2024-03-12 16:10:00'),
('Mariana', 'López', 'mariana.lopez@example.com', SHA2('ClienteDemo#07', 256), 'Av 6N # 28-50', 'Cali', 'Valle del Cauca', '1993-07-25', NULL, NULL, '2024-04-02 12:00:00'),
('Diego', 'Fernández', 'diego.fernandez@example.com', SHA2('ClienteDemo#08', 256), 'Cra 50 # 72-30', 'Barranquilla', 'Atlántico', '1982-02-14', NULL, NULL, '2024-04-20 17:40:00'),
('Isabella', 'Castro', 'isabella.castro@example.com', SHA2('ClienteDemo#09', 256), 'Calle 100 # 15-60', 'Bogotá', 'Cundinamarca', '2000-10-05', 1, 1, '2024-05-11 10:05:00'),
('Santiago', 'Morales', 'santiago.morales@example.com', SHA2('ClienteDemo#10', 256), 'Cra 70 # 33-22', 'Medellín', 'Antioquia', '1991-03-19', 2, NULL, '2024-06-01 09:50:00'),
('Daniela', 'Vargas', 'daniela.vargas@example.com', SHA2('ClienteDemo#11', 256), 'Calle 45 # 18-90', 'Bucaramanga', 'Santander', '1987-08-08', 3, 6, '2024-07-14 15:25:00'),
('Andrés', 'Peña', 'andres.pena@example.com', SHA2('ClienteDemo#12', 256), 'Cra 9 # 60-14', 'Bogotá', 'Cundinamarca', '1996-05-27', 1, NULL, '2024-08-09 13:15:00'),
('Paula', 'Rincón', 'paula.rincon@example.com', SHA2('ClienteDemo#13', 256), 'Av 4 # 10-25', 'Cali', 'Valle del Cauca', '1984-12-01', NULL, NULL, '2024-09-17 11:00:00'),
('Felipe', 'Cárdenas', 'felipe.cardenas@example.com', SHA2('ClienteDemo#14', 256), 'Cra 65 # 40-18', 'Medellín', 'Antioquia', '1998-09-09', 2, 10, '2025-01-05 10:30:00'),
('Camila', 'Ortiz', 'camila.ortiz@example.com', SHA2('ClienteDemo#15', 256), 'Calle 36 # 27-05', 'Bucaramanga', 'Santander', '1992-04-04', 3, NULL, '2025-03-22 09:00:00');

-- ---------------------------------------------------------------------
-- ventas (28 registros, distribuidos en fechas/horas/estados variados)
-- ---------------------------------------------------------------------
INSERT INTO ventas (id_cliente, id_sucursal, fecha_venta, estado) VALUES
(1, 1, '2024-02-01 10:15:00', 'Entregado'),   -- 1
(1, 1, '2024-05-10 16:40:00', 'Entregado'),   -- 2
(2, 1, '2024-02-14 11:00:00', 'Entregado'),   -- 3
(2, 1, '2024-08-22 19:05:00', 'Entregado'),   -- 4
(3, 2, '2024-03-01 09:30:00', 'Entregado'),   -- 5
(3, 2, '2024-09-18 13:20:00', 'Cancelado'),   -- 6
(4, 2, '2024-03-20 20:10:00', 'Entregado'),   -- 7
(5, 3, '2024-04-02 08:45:00', 'Entregado'),   -- 8
(5, 3, '2024-07-19 12:00:00', 'Entregado'),   -- 9
(6, 3, '2024-04-15 17:25:00', 'Entregado'),   -- 10
(7, 1, '2024-05-05 10:50:00', 'Entregado'),   -- 11
(8, 1, '2024-05-22 21:15:00', 'Entregado'),   -- 12
(9, 1, '2024-06-01 14:00:00', 'Entregado'),   -- 13
(9, 1, '2024-10-14 15:30:00', 'Enviado'),     -- 14
(10, 2, '2024-06-18 09:00:00', 'Entregado'),  -- 15
(10, 2, '2024-12-05 18:45:00', 'Entregado'),  -- 16
(11, 3, '2024-07-25 11:10:00', 'Entregado'),  -- 17
(12, 1, '2024-08-15 22:00:00', 'Entregado'),  -- 18
(13, 2, '2024-09-30 10:20:00', 'Entregado'),  -- 19
(14, 2, '2025-02-10 16:00:00', 'Entregado'),  -- 20
(15, 3, '2025-04-08 13:45:00', 'Procesando'), -- 21
(1, 1, '2025-05-19 09:10:00', 'Entregado'),   -- 22
(3, 2, '2025-06-02 14:55:00', 'Entregado'),   -- 23
(5, 3, '2025-07-11 20:30:00', 'Entregado'),   -- 24
(9, 1, '2025-08-20 11:40:00', 'Entregado'),   -- 25
(10, 2, '2025-09-05 17:00:00', 'Pendiente de Pago'), -- 26
(6, 3, '2025-10-12 12:15:00', 'Entregado'),   -- 27
(2, 1, '2025-11-01 19:50:00', 'Entregado'),   -- 28
(3, 2, '2025-08-15 10:00:00', 'Entregado'),   -- 29 (antes de promo id 4, producto 11)
(3, 2, '2025-09-10 15:00:00', 'Entregado'),   -- 30 (durante promo id 4, producto 11)
(9, 1, '2025-10-05 11:00:00', 'Entregado');   -- 31 (despues de promo id 4, producto 11)

-- ---------------------------------------------------------------------
-- detalle_ventas (precio_unitario_congelado tomado del precio del
-- producto en el momento simulado de la compra)
-- ---------------------------------------------------------------------
INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
(1, 1, 1, 175000),  (1, 4, 2, 55000),
(2, 2, 1, 349000),  (2, 3, 1, 129000),
(3, 6, 1, 159000),  (3, 8, 3, 39000),
(4, 9, 1, 219000),  (4, 7, 1, 99000),
(5, 11, 1, 289000),
(6, 12, 1, 175000),
(7, 15, 2, 89000),  (7, 17, 1, 55000),
(8, 5, 1, 219000),
(9, 16, 1, 249000), (9, 17, 2, 55000),
(10, 19, 2, 45000), (10, 20, 1, 129000),
(11, 21, 2, 55000), (11, 22, 1, 79000),
(12, 24, 3, 49000),
(13, 1, 2, 189000), (13, 3, 1, 129000),
(14, 2, 1, 349000),
(15, 13, 1, 89000), (15, 14, 1, 65000),
(16, 11, 1, 289000),(16, 12, 1, 175000),
(17, 18, 1, 899000),
(18, 6, 2, 159000),
(19, 9, 1, 219000), (19, 10, 2, 45000),
(20, 23, 1, 135000),
(21, 7, 2, 99000),
(22, 1, 1, 189000), (22, 2, 1, 349000),
(23, 5, 1, 219000),
(24, 16, 1, 249000),
(25, 21, 1, 55000), (25, 22, 1, 79000),
(26, 8, 5, 39000),
(27, 17, 3, 55000),
(28, 9, 2, 219000), (28, 4, 1, 59000),
(29, 11, 1, 289000),
(30, 11, 2, 289000),
(31, 11, 1, 289000);

-- ---------------------------------------------------------------------
-- promociones (pasadas, activas y futuras, para probar la consulta
-- de impacto de promociones y el evento de desactivacion automatica)
-- ---------------------------------------------------------------------
INSERT INTO promociones (id_producto, porcentaje_descuento, fecha_inicio, fecha_fin, activo) VALUES
(1, 15.00, '2024-11-01 00:00:00', '2024-11-30 23:59:59', FALSE),
(9, 20.00, '2025-06-01 00:00:00', '2025-06-15 23:59:59', FALSE),
(16, 10.00, '2025-08-01 00:00:00', '2025-08-31 23:59:59', FALSE),
(11, 25.00, '2025-09-01 00:00:00', '2025-09-30 23:59:59', TRUE),
(3, 30.00, '2025-12-01 00:00:00', '2025-12-10 23:59:59', TRUE);

-- ---------------------------------------------------------------------
-- carritos y carrito_items (mezcla de carritos recientes y abandonados)
-- ---------------------------------------------------------------------
INSERT INTO carritos (id_cliente, fecha_creacion, fecha_actualizacion) VALUES
(7,  '2025-01-10 10:00:00', '2025-01-10 10:05:00'),
(8,  '2025-02-15 09:00:00', '2025-02-15 09:10:00'),
(13, '2025-03-01 20:00:00', '2025-03-01 20:15:00'),
(12, '2025-11-20 18:00:00', '2025-11-20 18:20:00'),
(15, '2025-11-25 12:00:00', '2025-11-25 12:10:00'),
(4,  '2024-12-05 08:00:00', '2024-12-05 08:05:00');

INSERT INTO carrito_items (id_carrito, id_producto, cantidad) VALUES
(1, 2, 1), (1, 19, 2),
(2, 10, 1),
(3, 6, 1), (3, 8, 2),
(4, 5, 1),
(5, 24, 2), (5, 17, 1),
(6, 14, 1), (6, 23, 1), (6, 12, 1);

-- ---------------------------------------------------------------------
-- producto_vistas (incluye vistas anonimas con id_cliente NULL)
-- ---------------------------------------------------------------------
INSERT INTO producto_vistas (id_producto, id_cliente, fecha_vista) VALUES
(1, 1, '2024-01-28 09:00:00'), (1, NULL, '2024-01-29 11:20:00'), (1, 2, '2024-02-10 15:00:00'),
(2, 1, '2024-05-08 10:00:00'), (2, NULL, '2024-05-09 14:00:00'),
(9, 4, '2024-03-18 19:00:00'), (9, NULL, '2024-03-19 20:00:00'), (9, NULL, '2024-03-19 21:15:00'),
(19, 7, '2025-01-09 09:30:00'), (19, NULL, '2025-01-09 12:00:00'), (19, NULL, '2025-01-10 08:00:00'),
(20, NULL, '2025-01-11 10:00:00'), (20, NULL, '2025-01-12 11:00:00'), (20, 12, '2025-01-15 13:00:00'),
(16, 5, '2024-07-15 08:00:00'), (16, NULL, '2024-07-16 09:00:00'),
(23, NULL, '2025-02-01 10:00:00'), (23, NULL, '2025-02-02 11:00:00'),
(11, 3, '2024-02-25 09:00:00'), (11, 10, '2024-06-15 10:00:00');

-- ---------------------------------------------------------------------
-- resenas (clientes que efectivamente compraron el producto)
-- ---------------------------------------------------------------------
INSERT INTO resenas (id_producto, id_cliente, calificacion, comentario, fecha_resena) VALUES
(1, 1, 5, 'Excelente calidad de sonido y muy cómodos.', '2024-02-05 12:00:00'),
(2, 1, 4, 'Buena batería, la app podría mejorar.', '2024-05-15 16:00:00'),
(6, 2, 5, 'Muy buena chaqueta para la lluvia.', '2024-02-20 10:00:00'),
(11, 3, 4, 'Cocinan parejo, buen antiadherente.', '2024-03-08 09:00:00'),
(15, 4, 5, 'Balón oficial, excelente bote.', '2024-03-25 18:00:00'),
(18, 11, 3, 'Buena bicicleta pero un poco ruidosa.', '2024-08-01 11:00:00'),
(21, 7, 5, 'Historia envolvente, la recomiendo.', '2024-05-12 20:00:00'),
(24, 8, 4, 'Correa resistente, buen tamaño.', '2024-05-28 09:00:00'),
(9, 13, 4, 'Cómodas para uso diario.', '2024-10-05 14:00:00'),
(16, 5, 5, 'Muy útiles para entrenar en casa.', '2024-04-10 07:00:00');

-- =====================================================================
-- SECCION 7: RECALCULO DE CAMPOS DERIVADOS
-- =====================================================================

-- Desactivar temporalmente Safe Updates para permitir UPDATEs masivos
SET SQL_SAFE_UPDATES = 0;

UPDATE ventas v
SET v.total = (
    SELECT COALESCE(SUM(d.cantidad * d.precio_unitario_congelado), 0)
    FROM detalle_ventas d
    WHERE d.id_venta = v.id_venta
);

UPDATE clientes c
SET c.total_gastado = (
        SELECT COALESCE(SUM(v.total), 0)
        FROM ventas v
        WHERE v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'
    ),
    c.fecha_ultimo_pedido = (
        SELECT MAX(v.fecha_venta)
        FROM ventas v
        WHERE v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'
    );

UPDATE clientes
SET nivel_lealtad = CASE
    WHEN total_gastado >= 700000 THEN 'Oro'
    WHEN total_gastado >= 300000 THEN 'Plata'
    ELSE 'Bronce'
END;

UPDATE categorias c
SET c.contador_productos = (
    SELECT COUNT(*) FROM productos p WHERE p.id_categoria = c.id_categoria
);

-- Volver a activar Safe Updates por seguridad
SET SQL_SAFE_UPDATES = 1;

