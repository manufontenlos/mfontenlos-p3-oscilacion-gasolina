use database fuel_prices;

CREATE SCHEMA IF NOT EXISTS GOLD;

USE SCHEMA GOLD;


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

