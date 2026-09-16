Proyecto de Base de Datos para un E-commerce
Descripción
Este proyecto consiste en el diseño e implementación del núcleo relacional de una base de datos para una plataforma de comercio electrónico en MySQL 8.x. El sistema gestiona todo el ciclo de vida operativo del e-commerce, abarcando desde el catálogo de productos, inventario, categorías y proveedores, hasta la gestión de clientes, transacciones de venta y detalles de órdenes. Además, incluye una capa avanzada de analítica de negocio, lógica transaccional, automatización mediante eventos y disparadores, y un esquema riguroso de seguridad basado en roles y mínimos privilegios.

Autor
Juliana Cañizares

Instrucciones de Ejecución
Para garantizar la construcción correcta de la base de datos sin conflictos de dependencias entre tablas, funciones, disparadores y procedimientos, ejecute los scripts SQL estrictamente en el siguiente orden:

01_Esquema_y_Datos.sql

Crea la base de datos ecommerce_db, la estructura completa de tablas principales (con sus claves primarias, foráneas e índices) y realiza la carga de datos iniciales.

03_Funciones.sql

Implementa las 20 Funciones Definidas por el Usuario (UDFs) para encapsular reglas y cálculos reutilizables de negocio.

04_Seguridad.sql

Crea los roles de usuario, define permisos por columna/tabla, aplica políticas de contraseñas y configura las vistas de seguridad y aislamiento por sucursal.

05_Triggers.sql

Establece los 20 disparadores automáticos para auditoría de cambios de precios, control de stock y consistencia de datos.

06_Eventos.sql

Activa el programador de eventos (event_scheduler) y registra los 20 eventos programados para mantenimiento, limpieza y generación de KPIs.

07_Procedimientos.sql

Crea los 20 procedimientos almacenados transaccionales (START TRANSACTION, COMMIT, ROLLBACK) y otorga los permisos finales de ejecución.

02_Consultas_Avanzadas.sql

Contiene las 20 consultas complejas de analítica y reporteo (RFM, Cohort, Top ventas, rotación de inventario) para validar el funcionamiento y extraer inteligencia de negocio.
