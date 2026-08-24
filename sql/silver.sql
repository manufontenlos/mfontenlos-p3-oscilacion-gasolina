Use database fuel_prices

CREATE SCHEMA SILVER;

use schema silver;

CREATE OR REPLACE TABLE SILVER.DIM_STATION (
    IDEESS       VARCHAR NOT NULL,
    ROTULO       VARCHAR,
    DIRECCION    VARCHAR,
    MUNICIPIO    VARCHAR,
    PROVINCIA    VARCHAR,
    CCAA         VARCHAR,
    LAT          NUMBER(10,6),
    LON          NUMBER(10,6),

    CONSTRAINT PK_DIM_STATION PRIMARY KEY (IDEESS)
);

CREATE OR REPLACE TABLE SILVER.FCT_PRICE_SNAPSHOT (
    INGESTION_TS  TIMESTAMP_TZ NOT NULL,
    IDEESS        VARCHAR NOT NULL,
    PRODUCT       VARCHAR NOT NULL,
    PRICE_EUR_L   NUMBER(10,3),

    CONSTRAINT PK_FCT_PRICE_SNAPSHOT
        PRIMARY KEY (INGESTION_TS, IDEESS, PRODUCT)
);


--------- CARGA DE DIM_STATION --------------------


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

select * from fct_price_snapshot where IDEESS = '514' order by product, ingestion_ts;

select * from dim_station where municipio = 'Outes';

select count(distinct ingestion_ts) from fct_price_snapshot;

DESC TABLE SILVER.fct_price_snapshot;

DESC TABLE SILVER.dim_station;