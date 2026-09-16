-- =====================================================================
-- 02_Consultas_Avanzadas.sql
-- =====================================================================

USE ecommerce_db;

-- ---------------------------------------------------------------------
-- 1. Top 10 Productos Mas Vendidos
-- Ranking de los 10 productos que han generado mas ingresos (se
-- excluyen ventas canceladas).
-- ---------------------------------------------------------------------
SELECT
    p.id_producto,
    p.nombre,
    SUM(d.cantidad)                          AS unidades_vendidas,
    SUM(d.cantidad * d.precio_unitario_congelado) AS ingresos_totales
FROM detalle_ventas d
JOIN ventas v     ON v.id_venta = d.id_venta
JOIN productos p  ON p.id_producto = d.id_producto
WHERE v.estado <> 'Cancelado'
GROUP BY p.id_producto, p.nombre
ORDER BY ingresos_totales DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- 2. Productos con Bajas Ventas
-- Identifica el 10% inferior de productos por ingresos generados
-- (incluye productos sin ninguna venta, que caen naturalmente en el
-- decil mas bajo) para evaluar su descontinuacion.
-- ---------------------------------------------------------------------
WITH detalle_valido AS (
    SELECT d.id_producto, d.cantidad, d.precio_unitario_congelado
    FROM detalle_ventas d
    JOIN ventas v ON v.id_venta = d.id_venta
    WHERE v.estado <> 'Cancelado'
),
ventas_por_producto AS (
    SELECT
        p.id_producto,
        p.nombre,
        COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0) AS ingresos
    FROM productos p
    LEFT JOIN detalle_valido dv ON dv.id_producto = p.id_producto
    GROUP BY p.id_producto, p.nombre
),
ranked AS (
    SELECT
        id_producto, nombre, ingresos,
        NTILE(10) OVER (ORDER BY ingresos ASC) AS decil
    FROM ventas_por_producto
)
SELECT id_producto, nombre, ingresos
FROM ranked
WHERE decil = 1
ORDER BY ingresos ASC;

-- ---------------------------------------------------------------------
-- 3. Clientes VIP
-- Los 5 clientes con mayor valor de vida (LTV), segun su gasto total
-- historico en ventas no canceladas.
-- ---------------------------------------------------------------------
SELECT
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    COALESCE(SUM(v.total), 0) AS valor_vida_cliente
FROM clientes c
LEFT JOIN ventas v ON v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'
GROUP BY c.id_cliente, cliente
ORDER BY valor_vida_cliente DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- 4. Analisis de Ventas Mensuales
-- Ventas totales agrupadas por mes y ano.
-- ---------------------------------------------------------------------
SELECT
    DATE_FORMAT(fecha_venta, '%Y-%m') AS periodo,
    COUNT(*)                          AS num_ventas,
    SUM(total)                        AS ingresos_totales
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY periodo
ORDER BY periodo;

-- ---------------------------------------------------------------------
-- 5. Crecimiento de Clientes
-- Numero de nuevos clientes registrados por trimestre.
-- ---------------------------------------------------------------------
SELECT
    CONCAT(YEAR(fecha_registro), '-Q', QUARTER(fecha_registro)) AS trimestre,
    COUNT(*) AS nuevos_clientes
FROM clientes
GROUP BY trimestre
ORDER BY trimestre ASC;

-- ---------------------------------------------------------------------
-- 6. Tasa de Compra Repetida
-- Porcentaje de clientes (con al menos una compra) que han comprado
-- mas de una vez.
-- ---------------------------------------------------------------------
WITH compras_cliente AS (
    SELECT id_cliente, COUNT(*) AS num_compras
    FROM ventas
    WHERE estado <> 'Cancelado'
    GROUP BY id_cliente
)
SELECT
    (SELECT COUNT(*) FROM compras_cliente)                     AS clientes_con_compra,
    (SELECT COUNT(*) FROM compras_cliente WHERE num_compras>1) AS clientes_recurrentes,
    ROUND(
        100.0 * (SELECT COUNT(*) FROM compras_cliente WHERE num_compras > 1)
        / NULLIF((SELECT COUNT(*) FROM compras_cliente), 0), 2
    ) AS porcentaje_recurrencia;

-- ---------------------------------------------------------------------
-- 7. Productos Comprados Juntos Frecuentemente
-- Pares de productos que aparecen juntos en la misma venta con mayor
-- frecuencia (afinidad de productos / "market basket").
-- ---------------------------------------------------------------------
SELECT
    d1.id_producto AS producto_a, p1.nombre AS nombre_a,
    d2.id_producto AS producto_b, p2.nombre AS nombre_b,
    COUNT(*) AS veces_comprados_juntos
FROM detalle_ventas d1
JOIN detalle_ventas d2 ON d1.id_venta = d2.id_venta AND d1.id_producto < d2.id_producto
JOIN ventas v          ON v.id_venta = d1.id_venta AND v.estado <> 'Cancelado'
JOIN productos p1      ON p1.id_producto = d1.id_producto
JOIN productos p2      ON p2.id_producto = d2.id_producto
GROUP BY d1.id_producto, p1.nombre, d2.id_producto, p2.nombre
ORDER BY veces_comprados_juntos DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- 8. Rotacion de Inventario por Categoria
-- Unidades vendidas frente al stock actual, como indicador de rotacion
-- (mayor indice = el inventario se mueve mas rapido).
-- ---------------------------------------------------------------------
WITH detalle_valido AS (
    SELECT d.id_producto, d.cantidad
    FROM detalle_ventas d
    JOIN ventas v ON v.id_venta = d.id_venta
    WHERE v.estado <> 'Cancelado'
),
ventas_producto AS (
    SELECT
        p.id_producto, p.id_categoria, p.stock,
        COALESCE(SUM(dv.cantidad), 0) AS unidades_vendidas
    FROM productos p
    LEFT JOIN detalle_valido dv ON dv.id_producto = p.id_producto
    GROUP BY p.id_producto, p.id_categoria, p.stock
)
SELECT
    c.id_categoria,
    c.nombre AS categoria,
    SUM(vp.unidades_vendidas) AS unidades_vendidas,
    SUM(vp.stock)             AS stock_actual_total,
    ROUND(SUM(vp.unidades_vendidas) / NULLIF(SUM(vp.stock), 0), 2) AS indice_rotacion
FROM ventas_producto vp
JOIN categorias c ON c.id_categoria = vp.id_categoria
GROUP BY c.id_categoria, c.nombre
ORDER BY indice_rotacion DESC;

-- ---------------------------------------------------------------------
-- 9. Productos que Necesitan Reabastecimiento
-- Productos activos cuyo stock actual esta por debajo de su umbral
-- minimo (stock_minimo).
-- ---------------------------------------------------------------------
SELECT
    id_producto, nombre, stock, stock_minimo,
    (stock_minimo - stock) AS unidades_faltantes
FROM productos
WHERE stock < stock_minimo AND activo = TRUE
ORDER BY unidades_faltantes DESC;

-- ---------------------------------------------------------------------
-- 10. Analisis de Carrito Abandonado (simulado)
-- Carritos que llevan mas de 72 horas sin actualizarse y cuyo cliente
-- no completo ninguna venta en las 72 horas posteriores a esa
-- inactividad.
-- ---------------------------------------------------------------------
SELECT
    ca.id_carrito,
    ca.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido) AS cliente,
    ca.fecha_actualizacion,
    COUNT(ci.id_item)                       AS items_en_carrito,
    SUM(ci.cantidad * p.precio)             AS valor_estimado_carrito
FROM carritos ca
JOIN clientes c       ON c.id_cliente = ca.id_cliente
JOIN carrito_items ci ON ci.id_carrito = ca.id_carrito
JOIN productos p      ON p.id_producto = ci.id_producto
WHERE ca.fecha_actualizacion < (NOW() - INTERVAL 72 HOUR)
  AND NOT EXISTS (
        SELECT 1 FROM ventas v
        WHERE v.id_cliente = ca.id_cliente
          AND v.fecha_venta BETWEEN ca.fecha_actualizacion
                                 AND (ca.fecha_actualizacion + INTERVAL 72 HOUR)
      )
GROUP BY ca.id_carrito, ca.id_cliente, cliente, ca.fecha_actualizacion
ORDER BY ca.fecha_actualizacion;

-- ---------------------------------------------------------------------
-- 11. Rendimiento de Proveedores
-- Clasifica a los proveedores segun el volumen (unidades) e ingresos
-- generados por los productos que suministran.
-- ---------------------------------------------------------------------
WITH detalle_valido AS (
    SELECT d.id_producto, d.cantidad, d.precio_unitario_congelado
    FROM detalle_ventas d
    JOIN ventas v ON v.id_venta = d.id_venta
    WHERE v.estado <> 'Cancelado'
)
SELECT
    pr.id_proveedor,
    pr.nombre AS proveedor,
    COALESCE(SUM(dv.cantidad), 0) AS unidades_vendidas,
    COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0) AS ingresos_generados,
    RANK() OVER (ORDER BY COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0) DESC) AS ranking
FROM proveedores pr
JOIN productos p            ON p.id_proveedor = pr.id_proveedor
LEFT JOIN detalle_valido dv ON dv.id_producto = p.id_producto
GROUP BY pr.id_proveedor, pr.nombre
ORDER BY ingresos_generados DESC;

-- ---------------------------------------------------------------------
-- 12. Analisis Geografico de Ventas
-- Agrupa las ventas por ciudad del cliente.
-- ---------------------------------------------------------------------
SELECT
    c.ciudad,
    COUNT(v.id_venta) AS num_ventas,
    SUM(v.total)       AS ingresos_totales
FROM ventas v
JOIN clientes c ON c.id_cliente = v.id_cliente
WHERE v.estado <> 'Cancelado'
GROUP BY c.ciudad
ORDER BY ingresos_totales DESC;

-- ---------------------------------------------------------------------
-- 13. Ventas por Hora del Dia
-- Determina las horas pico de compra para optimizar campanas.
-- ---------------------------------------------------------------------
SELECT
    HOUR(fecha_venta) AS hora_del_dia,
    COUNT(*)            AS num_ventas,
    SUM(total)           AS ingresos
FROM ventas
WHERE estado <> 'Cancelado'
GROUP BY hora_del_dia
ORDER BY hora_del_dia;

-- ---------------------------------------------------------------------
-- 14. Impacto de Promociones
-- Compara las unidades vendidas de un producto en los 30 dias antes,
-- durante y 30 dias despues de una campana de descuento.
-- Cambiar el valor de id_promocion para analizar otra promocion.
-- ---------------------------------------------------------------------
WITH promo AS (
    SELECT id_producto, fecha_inicio, fecha_fin
    FROM promociones
    WHERE id_promocion = 4
)
SELECT 'Antes' AS periodo, COALESCE(SUM(d.cantidad), 0) AS unidades_vendidas
FROM promo pr
JOIN detalle_ventas d ON d.id_producto = pr.id_producto
JOIN ventas v         ON v.id_venta = d.id_venta AND v.estado <> 'Cancelado'
WHERE v.fecha_venta < pr.fecha_inicio
  AND v.fecha_venta >= (pr.fecha_inicio - INTERVAL 30 DAY)

UNION ALL

SELECT 'Durante', COALESCE(SUM(d.cantidad), 0)
FROM promo pr
JOIN detalle_ventas d ON d.id_producto = pr.id_producto
JOIN ventas v         ON v.id_venta = d.id_venta AND v.estado <> 'Cancelado'
WHERE v.fecha_venta BETWEEN pr.fecha_inicio AND pr.fecha_fin

UNION ALL

SELECT 'Despues', COALESCE(SUM(d.cantidad), 0)
FROM promo pr
JOIN detalle_ventas d ON d.id_producto = pr.id_producto
JOIN ventas v         ON v.id_venta = d.id_venta AND v.estado <> 'Cancelado'
WHERE v.fecha_venta > pr.fecha_fin
  AND v.fecha_venta <= (pr.fecha_fin + INTERVAL 30 DAY);

-- ---------------------------------------------------------------------
-- 15. Analisis de Cohort
-- Retencion de clientes mes a mes, agrupados por el mes de su primera
-- compra (cohorte).
-- ---------------------------------------------------------------------
WITH primera_compra AS (
    SELECT id_cliente, DATE_FORMAT(MIN(fecha_venta), '%Y-%m-01') AS mes_cohorte
    FROM ventas
    WHERE estado <> 'Cancelado'
    GROUP BY id_cliente
),
compras_mensuales AS (
    SELECT id_cliente, DATE_FORMAT(fecha_venta, '%Y-%m-01') AS mes_compra
    FROM ventas
    WHERE estado <> 'Cancelado'
    GROUP BY id_cliente, DATE_FORMAT(fecha_venta, '%Y-%m-01')
)
SELECT
    pc.mes_cohorte,
    TIMESTAMPDIFF(MONTH, pc.mes_cohorte, cm.mes_compra) AS mes_relativo,
    COUNT(DISTINCT cm.id_cliente) AS clientes_activos
FROM primera_compra pc
JOIN compras_mensuales cm ON cm.id_cliente = pc.id_cliente
GROUP BY pc.mes_cohorte, mes_relativo
ORDER BY pc.mes_cohorte, mes_relativo;

-- ---------------------------------------------------------------------
-- 16. Margen de Beneficio por Producto
-- Margen absoluto y porcentual de cada producto (precio vs. costo).
-- ---------------------------------------------------------------------
SELECT
    id_producto, nombre, precio, costo,
    (precio - costo) AS margen_absoluto,
    ROUND(((precio - costo) / precio) * 100, 2) AS margen_porcentual
FROM productos
ORDER BY margen_porcentual DESC;

-- ---------------------------------------------------------------------
-- 17. Tiempo Promedio Entre Compras
-- Numero promedio de dias que tarda cada cliente en volver a comprar.
-- ---------------------------------------------------------------------
WITH ventas_ordenadas AS (
    SELECT
        id_cliente, fecha_venta,
        LAG(fecha_venta) OVER (PARTITION BY id_cliente ORDER BY fecha_venta) AS fecha_venta_anterior
    FROM ventas
    WHERE estado <> 'Cancelado'
)
SELECT
    id_cliente,
    ROUND(AVG(TIMESTAMPDIFF(DAY, fecha_venta_anterior, fecha_venta)), 1) AS promedio_dias_entre_compras
FROM ventas_ordenadas
WHERE fecha_venta_anterior IS NOT NULL
GROUP BY id_cliente
ORDER BY promedio_dias_entre_compras;

-- ---------------------------------------------------------------------
-- 18. Productos Mas Vistos vs. Comprados
-- Compara el numero de visualizaciones con las unidades efectivamente
-- compradas, para medir la tasa de conversion por producto.
-- ---------------------------------------------------------------------
WITH vistas AS (
    SELECT id_producto, COUNT(*) AS num_vistas
    FROM producto_vistas
    GROUP BY id_producto
),
compras AS (
    SELECT d.id_producto, SUM(d.cantidad) AS unidades_compradas
    FROM detalle_ventas d
    JOIN ventas v ON v.id_venta = d.id_venta
    WHERE v.estado <> 'Cancelado'
    GROUP BY d.id_producto
)
SELECT
    p.id_producto, p.nombre,
    COALESCE(vi.num_vistas, 0)          AS vistas,
    COALESCE(co.unidades_compradas, 0)  AS compras,
    ROUND(COALESCE(co.unidades_compradas, 0) / NULLIF(vi.num_vistas, 0), 2) AS tasa_conversion
FROM productos p
LEFT JOIN vistas vi   ON vi.id_producto = p.id_producto
LEFT JOIN compras co  ON co.id_producto = p.id_producto
WHERE vi.num_vistas IS NOT NULL OR co.unidades_compradas IS NOT NULL
ORDER BY vistas DESC;

-- ---------------------------------------------------------------------
-- 19. Segmentacion de Clientes (RFM)
-- Clasifica a los clientes en cuartiles de Recencia, Frecuencia y
-- Valor Monetario. Un segmento "111" es el mas valioso (mas reciente,
-- mas frecuente, mayor gasto).
-- ---------------------------------------------------------------------
WITH rfm_base AS (
    SELECT
        c.id_cliente,
        DATEDIFF((SELECT MAX(fecha_venta) FROM ventas WHERE estado <> 'Cancelado'), MAX(v.fecha_venta)) AS recencia_dias,
        COUNT(v.id_venta) AS frecuencia,
        SUM(v.total)      AS monetario
    FROM clientes c
    JOIN ventas v ON v.id_cliente = c.id_cliente AND v.estado <> 'Cancelado'
    GROUP BY c.id_cliente
),
rfm_scored AS (
    SELECT
        id_cliente, recencia_dias, frecuencia, monetario,
        NTILE(4) OVER (ORDER BY recencia_dias ASC) AS r_score,
        NTILE(4) OVER (ORDER BY frecuencia DESC)   AS f_score,
        NTILE(4) OVER (ORDER BY monetario DESC)    AS m_score
    FROM rfm_base
)
SELECT
    id_cliente, recencia_dias, frecuencia, monetario,
    r_score, f_score, m_score,
    CONCAT(r_score, f_score, m_score) AS segmento_rfm
FROM rfm_scored
ORDER BY r_score, f_score, m_score;

-- ---------------------------------------------------------------------
-- 20. Prediccion de Demanda Simple
-- Proyecta la demanda del proximo mes para una categoria usando un
-- promedio movil de 3 meses sobre las unidades vendidas.
-- Cambiar el filtro id_categoria para analizar otra categoria.
-- ---------------------------------------------------------------------
WITH ventas_mensuales_categoria AS (
    SELECT
        cat.id_categoria,
        DATE_FORMAT(v.fecha_venta, '%Y-%m') AS periodo,
        SUM(d.cantidad) AS unidades
    FROM detalle_ventas d
    JOIN ventas v      ON v.id_venta = d.id_venta AND v.estado <> 'Cancelado'
    JOIN productos p   ON p.id_producto = d.id_producto
    JOIN categorias cat ON cat.id_categoria = p.id_categoria
    WHERE cat.id_categoria = 1
    GROUP BY cat.id_categoria, periodo
)
SELECT
    id_categoria, periodo, unidades,
    ROUND(
        AVG(unidades) OVER (ORDER BY periodo ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1
    ) AS promedio_movil_3_meses,
    ROUND(
        AVG(unidades) OVER (ORDER BY periodo ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1
    ) AS prediccion_proximo_mes
FROM ventas_mensuales_categoria
ORDER BY periodo;
