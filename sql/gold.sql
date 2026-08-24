use database fuel_prices;

CREATE SCHEMA GOLD;

---------- Dimensión de estación  ----------------

CREATE TABLE FUEL_PRICES.GOLD.DIM_STATION (
    STATION_KEY NUMBER(38,0),
    IDEESS VARCHAR,
    ROTULO VARCHAR,
    DIRECCION VARCHAR,
    MUNICIPIO VARCHAR,
    PROVINCIA VARCHAR,
    CCAA VARCHAR,
    LAT NUMBER(10,6),
    LON NUMBER(10,6)
);

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

CREATE TABLE FUEL_PRICES.GOLD.DIM_PRODUCT (
    PRODUCT_KEY NUMBER(38,0),
    PRODUCT VARCHAR
);

MERGE INTO FUEL_PRICES.GOLD.DIM_PRODUCT AS target

USING (
    SELECT COLUMN1 AS PRODUCT
    FROM VALUES
        ('Gasóleo A'),
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
            WHEN 'Gasóleo A' THEN 1
            WHEN 'Gasolina 95' THEN 2
            WHEN 'AdBlue' THEN 3
        END,
        source.PRODUCT
    );

--------- TABLA DE TIEMPO ----------------

CREATE TABLE FUEL_PRICES.GOLD.DIM_DATETIME (
    DATETIME_KEY NUMBER(38,0),
    INGESTION_TS TIMESTAMP_TZ,
    FECHA DATE,
    HORA TIME,
    DIA NUMBER,
    MES NUMBER,
    ANO NUMBER
);

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

CREATE TABLE FUEL_PRICES.GOLD.FACT_FUEL_PRICE (
    STATION_KEY NUMBER(38,0),
    PRODUCT_KEY NUMBER(38,0),
    DATETIME_KEY NUMBER(38,0),
    IDEESS VARCHAR,
    INGESTION_TS TIMESTAMP_TZ,
    PRICE_EUR_L NUMBER(10,3)
);

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

------------- COMPROBAMOS TABLAS ------------

SELECT COUNT(*) FROM gold.dim_station;

select count(*) from gold.dim_product;

select count(*) from gold.dim_datetime;

select count(*) from gold.fact_fuel_price;


-------------- COMPROBAMOS GRANULARIDAD --------------

SELECT
    IDEESS,
    PRODUCT_KEY,
    INGESTION_TS,
    COUNT(*) AS NUM_REGISTROS
FROM GOLD.FACT_FUEL_PRICE
GROUP BY
    IDEESS,
    PRODUCT_KEY,
    INGESTION_TS
HAVING COUNT(*) > 1;

SELECT
    PRODUCT,
    COUNT(*) AS NUM_REGISTROS
FROM SILVER.FCT_PRICE_SNAPSHOT
GROUP BY PRODUCT
ORDER BY PRODUCT;

SELECT
    COUNT(*) AS TOTAL,
    COUNT(DISTINCT INGESTION_TS) AS SNAPSHOTS,
    COUNT(DISTINCT IDEESS) AS ESTACIONES
FROM SILVER.FCT_PRICE_SNAPSHOT;
