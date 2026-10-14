-- =====================================================================================
--  APLICATIVO MÓVIL DE TRANSPARENCIA DE PRECIOS
--  Script de creación de la base de datos
--
--  Gestor      : PostgreSQL 16 o superior (restricción RNF016)
--  Codificación: UTF-8
--  Base        : 15 tablas, 100 campos, 16 claves foráneas, 7 índices
--
--  Requiere un rol con privilegios para crear la extensión btree_gist y el rol
--  app_precios. Se ejecuta dentro de una base ya creada; ver scripts/instalar_bd.ps1.
--
--  Las reglas que aquí se implementan están documentadas en el Diccionario de Datos.
--  Cada restricción lleva el requisito o la regla de negocio que la justifica.
-- =====================================================================================

-- El archivo está en UTF-8. Sin esta línea, psql en Windows lo lee con la codificación
-- de la consola y las cadenas con tilde quedan dañadas, tanto en los datos semilla como
-- dentro de las restricciones CHECK que las contienen.
SET client_encoding = 'UTF8';

-- Necesaria para la restricción de exclusión de tarifas (sección 4.10 del diccionario).
CREATE EXTENSION IF NOT EXISTS btree_gist;


-- =====================================================================================
-- 1. SEGURIDAD Y CARGA DE DATOS
-- =====================================================================================

-- Administradores del panel. El consumidor no se registra (RNF003).
CREATE TABLE usuario (
    id_usuario       BIGSERIAL     PRIMARY KEY,
    correo           VARCHAR(120)  NOT NULL,
    contrasena_hash  CHAR(60)      NOT NULL,   -- bcrypt, 60 caracteres (RNF001)
    nombre           VARCHAR(120)  NOT NULL,
    rol              VARCHAR(20)   NOT NULL DEFAULT 'administrador',
    activo           BOOLEAN       NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_usuario_correo UNIQUE (correo),
    CONSTRAINT ck_usuario_rol    CHECK (rol IN ('administrador'))
);

-- Registro de cada archivo cargado. Sostiene la trazabilidad del RNF010.
CREATE TABLE carga_archivo (
    id_carga_archivo      BIGSERIAL     PRIMARY KEY,
    id_usuario            BIGINT        NOT NULL,
    nombre_archivo        VARCHAR(255)  NOT NULL,
    hash_archivo          CHAR(64)      NOT NULL,   -- SHA-256, impide cargar dos veces
    fuente                VARCHAR(30)   NOT NULL,
    fecha_carga           TIMESTAMPTZ   NOT NULL DEFAULT now(),
    registros_validos     INTEGER       NOT NULL,
    registros_rechazados  INTEGER       NOT NULL,
    -- El CU01 exige que el administrador revise el resumen y confirme antes de guardar.
    estado                VARCHAR(12)   NOT NULL DEFAULT 'pendiente',
    -- El archivo tal como se subió. Guarda la carga pendiente entre el resumen y la
    -- confirmación sin usar la memoria del servidor (AD10), y deja cada precio ligado
    -- al archivo exacto del que salió (RNF010). Nulo en las cargas históricas iniciales,
    -- que cargar_precios.py hizo desde CSV y no desde un archivo subido.
    contenido_archivo     BYTEA         NULL,
    CONSTRAINT uq_carga_hash    UNIQUE (hash_archivo),
    CONSTRAINT ck_carga_fuente  CHECK (fuente IN ('SISAP minorista',
                                                  'SISAP mayorista',
                                                  'precios por mercado')),
    CONSTRAINT ck_carga_conteos CHECK (registros_validos   >= 0
                                   AND registros_rechazados >= 0),
    CONSTRAINT ck_carga_estado  CHECK (estado IN ('pendiente',
                                                  'confirmada',
                                                  'descartada')),
    CONSTRAINT fk_carga_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario) ON DELETE RESTRICT
);

-- Motivo de los registros descartados. Lo exige el paso 10 del CU01.
CREATE TABLE carga_rechazo (
    id_carga_rechazo  BIGSERIAL    PRIMARY KEY,
    id_carga_archivo  BIGINT       NOT NULL,
    motivo            VARCHAR(60)  NOT NULL,
    cantidad          INTEGER      NOT NULL,
    CONSTRAINT uq_rechazo_carga_motivo UNIQUE (id_carga_archivo, motivo),
    CONSTRAINT ck_rechazo_motivo   CHECK (motivo IN ('duplicado',
                                                     'dato faltante',
                                                     'precio no válido',
                                                     'unidad desconocida',
                                                     'fecha fuera de rango')),
    CONSTRAINT ck_rechazo_cantidad CHECK (cantidad > 0),
    CONSTRAINT fk_rechazo_carga FOREIGN KEY (id_carga_archivo)
        REFERENCES carga_archivo (id_carga_archivo) ON DELETE CASCADE
);


-- =====================================================================================
-- 2. CATÁLOGO DE PRODUCTOS
-- =====================================================================================

CREATE TABLE producto (
    id_producto  BIGSERIAL     PRIMARY KEY,
    nombre       VARCHAR(120)  NOT NULL,
    activo       BOOLEAN       NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_producto_nombre UNIQUE (nombre)
);

-- Nivel al que se registran los precios y se pronostica (RN02).
CREATE TABLE variedad (
    id_variedad    BIGSERIAL      PRIMARY KEY,
    id_producto    BIGINT         NOT NULL,
    nombre         VARCHAR(120)   NOT NULL,
    unidad_origen  VARCHAR(20)    NOT NULL,
    factor_a_kg    NUMERIC(10,4)  NOT NULL,   -- conversión a kilogramos (RN10)
    activo         BOOLEAN        NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_variedad_producto_nombre UNIQUE (id_producto, nombre),
    CONSTRAINT ck_variedad_factor CHECK (factor_a_kg > 0),
    CONSTRAINT fk_variedad_producto FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto) ON DELETE RESTRICT
);


-- =====================================================================================
-- 3. MERCADOS Y DESPLAZAMIENTO
-- =====================================================================================

CREATE TABLE mercado (
    id_mercado        BIGSERIAL      PRIMARY KEY,
    nombre            VARCHAR(150)   NOT NULL,
    distrito          VARCHAR(80)    NOT NULL,
    -- La excepción EX3 del CU06 exige mostrar la dirección cuando el dispositivo
    -- del consumidor no tiene una aplicación de mapas instalada.
    direccion         VARCHAR(160)   NOT NULL,
    latitud           NUMERIC(9,6)   NOT NULL,
    longitud          NUMERIC(9,6)   NOT NULL,
    horario_atencion  VARCHAR(60)    NULL,
    activo            BOOLEAN        NOT NULL DEFAULT TRUE,   -- baja lógica (RN11)
    CONSTRAINT uq_mercado_nombre_distrito UNIQUE (nombre, distrito),
    CONSTRAINT ck_mercado_latitud  CHECK (latitud  BETWEEN  -90 AND  90),
    CONSTRAINT ck_mercado_longitud CHECK (longitud BETWEEN -180 AND 180)
);

-- Los cuatro modos que fija el R12. No los administra nadie.
CREATE TABLE modo_desplazamiento (
    id_modo_desplazamiento  SMALLSERIAL  PRIMARY KEY,
    nombre                  VARCHAR(40)  NOT NULL,
    activo                  BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_modo_nombre UNIQUE (nombre),
    CONSTRAINT ck_modo_nombre CHECK (nombre IN ('a pie',
                                                'transporte público',
                                                'taxi',
                                                'auto particular'))
);

-- Costo de referencia por modo, con vigencia para poder reproducir cálculos pasados (R5).
CREATE TABLE tarifa (
    id_tarifa               BIGSERIAL     PRIMARY KEY,
    id_modo_desplazamiento  SMALLINT      NOT NULL,
    tipo_cobro              VARCHAR(10)   NOT NULL,
    monto                   NUMERIC(8,2)  NOT NULL,
    vigente_desde           DATE          NOT NULL,
    vigente_hasta           DATE          NULL,
    CONSTRAINT ck_tarifa_tipo    CHECK (tipo_cobro IN ('fijo', 'por_km')),
    CONSTRAINT ck_tarifa_monto   CHECK (monto >= 0),           -- a pie: cero (RN07)
    CONSTRAINT ck_tarifa_periodo CHECK (vigente_hasta IS NULL
                                     OR vigente_hasta > vigente_desde),
    CONSTRAINT fk_tarifa_modo FOREIGN KEY (id_modo_desplazamiento)
        REFERENCES modo_desplazamiento (id_modo_desplazamiento) ON DELETE RESTRICT,
    -- Impide dos tarifas vigentes a la vez para el mismo modo: sin esto el cálculo
    -- del costo total no sería determinista (R14, RN07).
    CONSTRAINT ex_tarifa_sin_solape EXCLUDE USING gist (
        id_modo_desplazamiento WITH =,
        daterange(vigente_desde, COALESCE(vigente_hasta, 'infinity'::date), '[)') WITH &&
    )
);


-- =====================================================================================
-- 4. PRECIOS
-- =====================================================================================

-- Serie histórica de Lima. Es el insumo del modelo predictivo (RN02).
CREATE TABLE precio_serie (
    id_precio_serie   BIGSERIAL      PRIMARY KEY,
    id_variedad       BIGINT         NOT NULL,
    id_carga_archivo  BIGINT         NOT NULL,
    fecha             DATE           NOT NULL,
    ambito            VARCHAR(20)    NOT NULL,
    precio_kg         NUMERIC(10,2)  NOT NULL,
    -- Volumen mayorista ingresado ese día. El CU03 lo declara como variable de
    -- entrada del modelo. SISAP solo lo publica para los productos frescos y solo
    -- en el ámbito mayorista, de modo que admite nulos.
    volumen_t         NUMERIC(12,2)  NULL,
    CONSTRAINT uq_precio_serie UNIQUE (id_variedad, fecha, ambito),
    CONSTRAINT ck_precio_serie_ambito CHECK (ambito IN ('minorista_lima',
                                                        'mayorista_lima')),
    CONSTRAINT ck_precio_serie_monto  CHECK (precio_kg > 0),
    CONSTRAINT ck_precio_serie_volumen CHECK (volumen_t IS NULL OR volumen_t >= 0),
    -- El volumen solo tiene sentido en la serie mayorista.
    CONSTRAINT ck_precio_serie_volumen_ambito CHECK (
        volumen_t IS NULL OR ambito = 'mayorista_lima'),
    CONSTRAINT fk_precio_serie_variedad FOREIGN KEY (id_variedad)
        REFERENCES variedad (id_variedad) ON DELETE RESTRICT,
    CONSTRAINT fk_precio_serie_carga FOREIGN KEY (id_carga_archivo)
        REFERENCES carga_archivo (id_carga_archivo) ON DELETE RESTRICT
);

-- Precio vigente por mercado. Es lo que ve el consumidor (RN03).
CREATE TABLE precio_mercado (
    id_precio_mercado  BIGSERIAL      PRIMARY KEY,
    id_mercado         BIGINT         NOT NULL,
    id_variedad        BIGINT         NOT NULL,
    id_carga_archivo   BIGINT         NOT NULL,
    fecha              DATE           NOT NULL,
    precio_kg          NUMERIC(10,2)  NOT NULL,
    CONSTRAINT uq_precio_mercado UNIQUE (id_mercado, id_variedad, fecha),
    CONSTRAINT ck_precio_mercado_monto CHECK (precio_kg > 0),
    CONSTRAINT fk_precio_mercado_mercado FOREIGN KEY (id_mercado)
        REFERENCES mercado (id_mercado) ON DELETE RESTRICT,
    CONSTRAINT fk_precio_mercado_variedad FOREIGN KEY (id_variedad)
        REFERENCES variedad (id_variedad) ON DELETE RESTRICT,
    CONSTRAINT fk_precio_mercado_carga FOREIGN KEY (id_carga_archivo)
        REFERENCES carga_archivo (id_carga_archivo) ON DELETE RESTRICT
);


-- =====================================================================================
-- 5. MODELO PREDICTIVO
-- =====================================================================================

-- Única fuente de verdad sobre qué versión del modelo está en uso (RNF015).
CREATE TABLE modelo_version (
    id_modelo_version    BIGSERIAL     PRIMARY KEY,
    nombre_archivo       VARCHAR(255)  NOT NULL,
    algoritmo            VARCHAR(60)   NOT NULL,
    -- Qué salida produce el modelo: el nivel del precio pronosticado o la
    -- dirección del cambio semanal (R6). Se entrenan y se reemplazan por separado.
    proposito            VARCHAR(12)   NOT NULL,
    fecha_entrenamiento  TIMESTAMPTZ   NOT NULL,
    datos_desde          DATE          NOT NULL,
    datos_hasta          DATE          NOT NULL,
    vigente              BOOLEAN       NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_modelo_archivo   UNIQUE (nombre_archivo),
    CONSTRAINT ck_modelo_proposito CHECK (proposito IN ('nivel', 'tendencia')),
    CONSTRAINT ck_modelo_ventana   CHECK (datos_hasta > datos_desde)
);

-- Una sola versión vigente por propósito. El modelo de nivel y el de tendencia
-- conviven, pero de cada uno hay exactamente uno en uso a la vez (RNF015).
CREATE UNIQUE INDEX uq_modelo_vigente
    ON modelo_version (proposito) WHERE vigente;

-- Desempeño por variedad y horizonte (R7). id_variedad nulo = métrica global.
CREATE TABLE metrica_modelo (
    id_metrica_modelo      BIGSERIAL      PRIMARY KEY,
    id_modelo_version      BIGINT         NOT NULL,
    id_variedad            BIGINT         NULL,
    horizonte_semanas      SMALLINT       NOT NULL,
    mae                    NUMERIC(10,4)  NULL,
    wape                   NUMERIC(7,4)   NULL,
    mase                   NUMERIC(7,4)   NULL,
    exactitud_direccional  NUMERIC(5,4)   NULL,
    -- NULLS NOT DISTINCT evita que la métrica global se duplique (PostgreSQL 15+).
    CONSTRAINT uq_metrica UNIQUE NULLS NOT DISTINCT
        (id_modelo_version, id_variedad, horizonte_semanas),
    CONSTRAINT ck_metrica_horizonte CHECK (horizonte_semanas IN (1, 2)),   -- RN01
    CONSTRAINT ck_metrica_valores   CHECK (
            (mae   IS NULL OR mae   >= 0)
        AND (wape  IS NULL OR wape  >= 0)
        AND (mase  IS NULL OR mase  >= 0)
        AND (exactitud_direccional IS NULL
             OR exactitud_direccional BETWEEN 0 AND 1)),
    CONSTRAINT fk_metrica_modelo FOREIGN KEY (id_modelo_version)
        REFERENCES modelo_version (id_modelo_version) ON DELETE CASCADE,
    CONSTRAINT fk_metrica_variedad FOREIGN KEY (id_variedad)
        REFERENCES variedad (id_variedad) ON DELETE RESTRICT
);

-- Pronóstico a nivel de Lima Metropolitana por variedad (R6, RN02).
CREATE TABLE prediccion (
    id_prediccion       BIGSERIAL      PRIMARY KEY,
    id_variedad         BIGINT         NOT NULL,
    id_modelo_version   BIGINT         NOT NULL,   -- el de propósito 'nivel'
    id_modelo_tendencia BIGINT         NULL,       -- el de propósito 'tendencia'
    fecha_generacion    TIMESTAMPTZ    NOT NULL DEFAULT now(),
    fecha_ultimo_dato   DATE           NOT NULL,   -- se muestra al consumidor (R9)
    horizonte_semanas   SMALLINT       NOT NULL,
    -- Derivada: no se escribe a mano, así no puede contradecir a las otras dos.
    fecha_objetivo      DATE GENERATED ALWAYS AS
                        (fecha_ultimo_dato + (horizonte_semanas * 7)) STORED,
    precio_estimado_kg  NUMERIC(10,2)  NOT NULL,
    -- Salida del modelo de tendencia (R6). Queda nula en las variedades sin modelo
    -- direccional válido; el CU06 las informa como precio estable y no recomienda.
    tendencia           VARCHAR(12)    NULL,
    confianza_tendencia NUMERIC(5,4)   NULL,
    vigente             BOOLEAN        NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_prediccion UNIQUE
        (id_variedad, fecha_objetivo, horizonte_semanas, id_modelo_version),
    CONSTRAINT ck_prediccion_horizonte CHECK (horizonte_semanas IN (1, 2)),   -- RN01
    CONSTRAINT ck_prediccion_monto     CHECK (precio_estimado_kg > 0),
    CONSTRAINT ck_prediccion_tendencia CHECK (
        tendencia IS NULL OR tendencia IN ('sube', 'baja', 'se mantiene')),
    CONSTRAINT ck_prediccion_confianza CHECK (
        confianza_tendencia IS NULL OR confianza_tendencia BETWEEN 0 AND 1),
    -- La tendencia, su confianza y el modelo que la produjo van las tres o ninguna.
    -- Así no puede quedar una tendencia sin trazabilidad ni sin nivel de confianza.
    CONSTRAINT ck_prediccion_tendencia_completa CHECK (
           (tendencia IS     NULL AND confianza_tendencia IS     NULL
                                  AND id_modelo_tendencia IS     NULL)
        OR (tendencia IS NOT NULL AND confianza_tendencia IS NOT NULL
                                  AND id_modelo_tendencia IS NOT NULL)),
    CONSTRAINT fk_prediccion_variedad FOREIGN KEY (id_variedad)
        REFERENCES variedad (id_variedad) ON DELETE RESTRICT,
    CONSTRAINT fk_prediccion_modelo FOREIGN KEY (id_modelo_version)
        REFERENCES modelo_version (id_modelo_version) ON DELETE RESTRICT,
    CONSTRAINT fk_prediccion_modelo_tendencia FOREIGN KEY (id_modelo_tendencia)
        REFERENCES modelo_version (id_modelo_version) ON DELETE RESTRICT
);

-- Impide mostrar dos pronósticos distintos del mismo producto y semana (RNF009).
CREATE UNIQUE INDEX uq_prediccion_vigente
    ON prediccion (id_variedad, fecha_objetivo, horizonte_semanas) WHERE vigente;

-- Máximo tres factores por predicción (RN05).
CREATE TABLE factor_explicacion (
    id_factor_explicacion  BIGSERIAL      PRIMARY KEY,
    id_prediccion          BIGINT         NOT NULL,
    orden                  SMALLINT       NOT NULL,
    descripcion            VARCHAR(200)   NOT NULL,
    contribucion           NUMERIC(8,4)   NOT NULL,
    CONSTRAINT uq_factor_orden UNIQUE (id_prediccion, orden),
    CONSTRAINT ck_factor_orden CHECK (orden BETWEEN 1 AND 3),
    CONSTRAINT fk_factor_prediccion FOREIGN KEY (id_prediccion)
        REFERENCES prediccion (id_prediccion) ON DELETE CASCADE
);


-- =====================================================================================
-- 6. INDICADORES DE USO
-- =====================================================================================

-- Registro anónimo de cada comparación (R18). No contiene dato alguno que
-- identifique al consumidor (RN12, RNF003).
CREATE TABLE indicador_uso (
    id_indicador_uso         BIGSERIAL      PRIMARY KEY,
    id_mercado               BIGINT         NOT NULL,
    ocurrido_en              TIMESTAMPTZ    NOT NULL DEFAULT now(),
    segundos_hasta_eleccion  INTEGER        NOT NULL,
    tipo_referencia          VARCHAR(20)    NOT NULL,
    costo_elegido            NUMERIC(10,2)  NOT NULL,
    costo_referencia         NUMERIC(10,2)  NOT NULL,
    -- Derivada: el ahorro no puede contradecir a los costos que lo producen.
    ahorro_neto              NUMERIC(10,2) GENERATED ALWAYS AS
                             (costo_referencia - costo_elegido) STORED,
    CONSTRAINT ck_indicador_tipo CHECK (tipo_referencia IN ('mercado habitual',
                                                            'promedio de cercanos')),
    CONSTRAINT ck_indicador_montos CHECK (segundos_hasta_eleccion >= 0
                                      AND costo_elegido           >= 0
                                      AND costo_referencia        >= 0),
    CONSTRAINT fk_indicador_mercado FOREIGN KEY (id_mercado)
        REFERENCES mercado (id_mercado) ON DELETE RESTRICT
);


-- =====================================================================================
-- 7. ÍNDICES DE RENDIMIENTO
--    PostgreSQL ya crea un índice por cada clave primaria y cada restricción UNIQUE.
--    Estos cinco sostienen requisitos concretos.
-- =====================================================================================

-- RNF011: consulta de precios por mercado en 2 segundos.
CREATE INDEX ix_precio_mercado_consulta
    ON precio_mercado (id_mercado, id_variedad, fecha DESC);

-- RNF011 y R9: gráfico de las últimas 12 semanas.
CREATE INDEX ix_precio_serie_consulta
    ON precio_serie (id_variedad, ambito, fecha DESC);

-- RNF011: obtener el pronóstico vigente sin recorrer el histórico.
CREATE INDEX ix_prediccion_vigente
    ON prediccion (id_variedad, horizonte_semanas) WHERE vigente;

-- R13: listar los mercados cercanos dentro del radio de búsqueda.
CREATE INDEX ix_mercado_activo
    ON mercado (activo) WHERE activo;

-- R18: explotar los indicadores por periodo en el análisis de resultados.
CREATE INDEX ix_indicador_fecha
    ON indicador_uso (ocurrido_en);


-- =====================================================================================
-- 8. DATOS INICIALES
--    Solo los catálogos fijos. Los montos de las tarifas se cargan desde el panel
--    cuando se tengan los valores de referencia del transporte en Lima.
-- =====================================================================================

INSERT INTO modo_desplazamiento (nombre) VALUES
    ('a pie'),
    ('transporte público'),
    ('taxi'),
    ('auto particular');

-- El desplazamiento a pie no cuesta (RN07). Es el único monto que ya se conoce.
INSERT INTO tarifa (id_modo_desplazamiento, tipo_cobro, monto, vigente_desde)
SELECT id_modo_desplazamiento, 'fijo', 0, CURRENT_DATE
FROM modo_desplazamiento
WHERE nombre = 'a pie';


-- =====================================================================================
-- 9. PERMISOS SOBRE LOS DATOS DE PRECIOS
--    El RNF010 exige que un precio no pueda modificarse fuera del proceso de carga.
--    Esa regla se impone aquí, en la base, y no solo en el código de la API.
-- =====================================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_precios') THEN
        -- La contraseña NO se define aquí: se asigna aparte, desde una variable de
        -- entorno, para que nunca quede escrita en el repositorio.
        --     ALTER ROLE app_precios PASSWORD '...';
        CREATE ROLE app_precios LOGIN;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO app_precios;

GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA public TO app_precios;

GRANT USAGE, SELECT
    ON ALL SEQUENCES IN SCHEMA public TO app_precios;

-- Un precio cargado no se corrige editándolo: se corrige registrando una carga nueva.
REVOKE UPDATE, DELETE ON precio_serie   FROM app_precios;
REVOKE UPDATE, DELETE ON precio_mercado FROM app_precios;

-- =====================================================================================
-- Fin del script.
-- =====================================================================================
