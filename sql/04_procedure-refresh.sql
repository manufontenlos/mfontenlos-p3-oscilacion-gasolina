

CREATE OR REPLACE PROCEDURE FUEL_PRICES.SILVER.REFRESH_FUEL_DATA()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$

DECLARE
    V_INGESTION_TS TIMESTAMP_TZ;
    V_RAW_COUNT NUMBER;
    V_SILVER_COUNT NUMBER;
    V_GOLD_COUNT NUMBER;

BEGIN

    --------------------------------------------------
    -- OBTENER ÚLTIMA INGESTA
    --------------------------------------------------

    SELECT MAX(INGESTION_TS)
    INTO :V_INGESTION_TS
    FROM FUEL_PRICES.RAW.FUEL_PRICES_JSON;

    -- 1. Actualizar SILVER --------------

    
INSERT INTO SILVER.DIM_STATION (
    IDEESS,
    ROTULO,
    DIRECCION,
    MUNICIPIO,
    PROVINCIA,
    CCAA,
    LAT,
    LON
)
SELECT DISTINCT
    e.VALUE:"IDEESS"::VARCHAR AS IDEESS,

    TRIM(e.VALUE:"Rótulo"::VARCHAR) AS ROTULO,

    TRIM(e.VALUE:"Dirección"::VARCHAR) AS DIRECCION,

    TRIM(e.VALUE:"Municipio"::VARCHAR) AS MUNICIPIO,

    TRIM(e.VALUE:"Provincia"::VARCHAR) AS PROVINCIA,

    TRIM(e.VALUE:"CCAA"::VARCHAR) AS CCAA,

    TRY_TO_DECIMAL(
        REPLACE(
            e.VALUE:"Latitud"::VARCHAR,
            ',',
            '.'
        ),
        10,
        6
    ) AS LAT,

    TRY_TO_DECIMAL(
        REPLACE(
            e.VALUE:"Longitud (WGS84)"::VARCHAR,
            ',',
            '.'
        ),
        10,
        6
    ) AS LON

FROM RAW.FUEL_PRICES_JSON r,
LATERAL FLATTEN(
    INPUT => r.PAYLOAD:ListaEESSPrecio
) e

WHERE e.VALUE:"IDEESS" IS NOT NULL

AND NOT EXISTS (
    SELECT 1
    FROM SILVER.DIM_STATION d
    WHERE d.IDEESS = e.VALUE:"IDEESS"::VARCHAR
);


------------ CARGA DE TABLA DE PRECIOS -------------------------

INSERT INTO SILVER.FCT_PRICE_SNAPSHOT (
    INGESTION_TS,
    IDEESS,
    PRODUCT,
    PRICE_EUR_L
)

WITH STATIONS AS (

    SELECT
        r.INGESTION_ID,
        r.INGESTION_TS,
        e.VALUE
    FROM RAW.FUEL_PRICES_JSON r,
    LATERAL FLATTEN(
        INPUT => r.PAYLOAD:ListaEESSPrecio
    ) e

),

PRODUCTS AS (

    -- GASOLEO A
    SELECT
        INGESTION_ID,
        INGESTION_TS,
        VALUE:"IDEESS"::VARCHAR AS IDEESS,
        'Gasoleo A' AS PRODUCT,
        TRY_TO_DECIMAL(
            REPLACE(
                VALUE:"Precio Gasoleo A"::VARCHAR,
                ',',
                '.'
            ),
            10,
            3
        ) AS PRICE_EUR_L
    FROM STATIONS

    UNION ALL

    -- GASOLINA 95
    SELECT
        INGESTION_ID,
        INGESTION_TS,
        VALUE:"IDEESS"::VARCHAR AS IDEESS,
        'Gasolina 95' AS PRODUCT,
        TRY_TO_DECIMAL(
            REPLACE(
                VALUE:"Precio Gasolina 95 E5"::VARCHAR,
                ',',
                '.'
            ),
            10,
            3
        ) AS PRICE_EUR_L
    FROM STATIONS

    UNION ALL

    -- ADBLUE
    SELECT
        INGESTION_ID,
        INGESTION_TS,
        VALUE:"IDEESS"::VARCHAR AS IDEESS,
        'AdBlue' AS PRODUCT,
        TRY_TO_DECIMAL(
            REPLACE(
                VALUE:"Precio AdBlue"::VARCHAR,
                ',',
                '.'
            ),
            10,
            3
        ) AS PRICE_EUR_L
    FROM STATIONS
)

SELECT
    INGESTION_TS,
    IDEESS,
    PRODUCT,
    PRICE_EUR_L

FROM PRODUCTS

WHERE IDEESS IS NOT NULL

AND PRICE_EUR_L IS NOT NULL

AND NOT EXISTS (
    SELECT 1
    FROM SILVER.FCT_PRICE_SNAPSHOT f
    WHERE f.INGESTION_TS = PRODUCTS.INGESTION_TS
      AND f.IDEESS = PRODUCTS.IDEESS
      AND f.PRODUCT = PRODUCTS.PRODUCT
);


    

    -- 2. Actualizar GOLD  -------------------------

MERGE INTO FUEL_PRICES.GOLD.DIM_STATION AS target

USING (
    SELECT DISTINCT
        IDEESS,
        ROTULO,
        DIRECCION,
        MUNICIPIO,
        PROVINCIA,
        CCAA,
        LAT,
        LON
    FROM FUEL_PRICES.SILVER.DIM_STATION
) AS source

ON target.IDEESS = source.IDEESS

WHEN MATCHED THEN
    UPDATE SET
        target.ROTULO = source.ROTULO,
        target.DIRECCION = source.DIRECCION,
        target.MUNICIPIO = source.MUNICIPIO,
        target.PROVINCIA = source.PROVINCIA,
        target.CCAA = source.CCAA,
        target.LAT = source.LAT,
        target.LON = source.LON

WHEN NOT MATCHED THEN
    INSERT (
        STATION_KEY,
        IDEESS,
        ROTULO,
        DIRECCION,
        MUNICIPIO,
        PROVINCIA,
        CCAA,
        LAT,
        LON
    )
    VALUES (
        HASH(source.IDEESS),
        source.IDEESS,
        source.ROTULO,
        source.DIRECCION,
        source.MUNICIPIO,
        source.PROVINCIA,
        source.CCAA,
        source.LAT,
        source.LON
    );

----------- TABLA DE PRODUCTOS -------------

MERGE INTO FUEL_PRICES.GOLD.DIM_PRODUCT AS target

USING (
    SELECT COLUMN1 AS PRODUCT
    FROM VALUES
        ('Gasoleo A'),
        ('Gasolina 95'),
        ('AdBlue')
) AS source

ON target.PRODUCT = source.PRODUCT

WHEN NOT MATCHED THEN
    INSERT (
        PRODUCT_KEY,
        PRODUCT
    )
    VALUES (
        CASE source.PRODUCT
            WHEN 'Gasoleo A' THEN 1
            WHEN 'Gasolina 95' THEN 2
            WHEN 'AdBlue' THEN 3
        END,
        source.PRODUCT
    );

--------- TABLA DE TIEMPO ----------------


MERGE INTO FUEL_PRICES.GOLD.DIM_DATETIME AS target

USING (
    SELECT DISTINCT
        INGESTION_TS
    FROM FUEL_PRICES.SILVER.FCT_PRICE_SNAPSHOT
) AS source

ON target.INGESTION_TS = source.INGESTION_TS

WHEN NOT MATCHED THEN
    INSERT (
        DATETIME_KEY,
        INGESTION_TS,
        FECHA,
        HORA,
        DIA,
        MES,
        ANO
    )
    VALUES (
        HASH(source.INGESTION_TS),
        source.INGESTION_TS,
        CAST(source.INGESTION_TS AS DATE),
        CAST(source.INGESTION_TS AS TIME),
        DAY(source.INGESTION_TS),
        MONTH(source.INGESTION_TS),
        YEAR(source.INGESTION_TS)
    );
    
-------- TABLA DE HECHOS ----------------------


MERGE INTO FUEL_PRICES.GOLD.FACT_FUEL_PRICE AS target

USING (
    SELECT
        s.STATION_KEY,
        p.PRODUCT_KEY,
        d.DATETIME_KEY,
        f.IDEESS,
        f.INGESTION_TS,
        f.PRICE_EUR_L

    FROM FUEL_PRICES.SILVER.FCT_PRICE_SNAPSHOT f

    INNER JOIN FUEL_PRICES.GOLD.DIM_STATION s
        ON f.IDEESS = s.IDEESS

    INNER JOIN FUEL_PRICES.GOLD.DIM_PRODUCT p
        ON f.PRODUCT = p.PRODUCT

    INNER JOIN FUEL_PRICES.GOLD.DIM_DATETIME d
        ON f.INGESTION_TS = d.INGESTION_TS

    WHERE f.PRICE_EUR_L IS NOT NULL
) AS source

ON  target.IDEESS = source.IDEESS
AND target.PRODUCT_KEY = source.PRODUCT_KEY
AND target.INGESTION_TS = source.INGESTION_TS

WHEN MATCHED THEN
    UPDATE SET
        target.PRICE_EUR_L = source.PRICE_EUR_L

WHEN NOT MATCHED THEN
    INSERT (
        STATION_KEY,
        PRODUCT_KEY,
        DATETIME_KEY,
        IDEESS,
        INGESTION_TS,
        PRICE_EUR_L
    )
    VALUES (
        source.STATION_KEY,
        source.PRODUCT_KEY,
        source.DATETIME_KEY,
        source.IDEESS,
        source.INGESTION_TS,
        source.PRICE_EUR_L
    );


    -- 3. Registrar trazabilidad

    SELECT COUNT(*)
    INTO :V_RAW_COUNT
    FROM FUEL_PRICES.RAW.FUEL_PRICES_JSON;

    SELECT COUNT(*)
    INTO :V_SILVER_COUNT
    FROM FUEL_PRICES.SILVER.FCT_PRICE_SNAPSHOT;

    SELECT COUNT(*)
    INTO :V_GOLD_COUNT
    FROM FUEL_PRICES.GOLD.FACT_FUEL_PRICE;


    INSERT INTO FUEL_PRICES.SILVER.ETL_LOG
    (
        INGESTION_TS,
        RAW_COUNT,
        SILVER_COUNT,
        GOLD_COUNT,
        STATUS,
        MESSAGE
    )
    VALUES
    (
        :V_INGESTION_TS,
        :V_RAW_COUNT,
        :V_SILVER_COUNT,
        :V_GOLD_COUNT,
        'SUCCESS',
        'Actualización SILVER y GOLD completada'
    );

    RETURN 'OK';


EXCEPTION
    WHEN OTHER THEN

        INSERT INTO FUEL_PRICES.SILVER.ETL_LOG
        (
            INGESTION_TS,
            RAW_COUNT,
            SILVER_COUNT,
            GOLD_COUNT,
            STATUS,
            MESSAGE
        )
        VALUES
        (
            :V_INGESTION_TS,
            NULL,
            NULL,
            NULL,
            'ERROR',
            SQLERRM
        );

        RETURN 'ERROR: ' || SQLERRM;

END;
$$;


