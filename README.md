# Análisis de precios de carburantes en España

Sistema de captura, almacenamiento, transformación y análisis de los precios de carburantes de las estaciones de servicio de España.

El proyecto obtiene periódicamente los precios publicados por la **API de Precios de Carburantes del Ministerio**, conserva un histórico de las capturas y construye un modelo analítico en **Snowflake**, que posteriormente es explotado mediante **Power BI**.

La solución implementa una arquitectura de datos por capas:

**API → RAW → SILVER → GOLD → Power BI**

Además, el proceso está automatizado para realizar nuevas ingestas y actualizaciones cada **3 horas**.

---

## 1. Objetivo

El objetivo del proyecto es construir un sistema capaz de almacenar y analizar la evolución de los precios de los carburantes en las estaciones de servicio españolas.

El sistema permite analizar:

- La evolución histórica del precio de Gasóleo A.
- La evolución histórica del precio de Gasolina 95.
- Las variaciones de precio entre diferentes capturas.
- Los precios actuales de las estaciones de servicio.
- Las diferencias de precio entre provincias.
- Las diferencias de precio entre municipios.
- Las diferencias de precio entre operadores o rótulos.
- La evolución temporal de una estación concreta.
- La localización geográfica de las estaciones más baratas y más caras.

La información se captura periódicamente para poder construir un histórico de precios y estudiar su evolución.

---

# 2. Arquitectura

La arquitectura completa del sistema es la siguiente:

```text
                         API DE PRECIOS
                        DE CARBURANTES
                              │
                              │ HTTP / JSON
                              ▼
                    ┌─────────────────────┐
                    │       PYTHON        │
                    │                     │
                    │ Script de ingesta   │
                    └──────────┬──────────┘
                               │
                               │ cada 3 horas
                               ▼
                    ┌─────────────────────┐
                    │   GITHUB ACTIONS    │
                    │                     │
                    │ Automatización      │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │       SNOWFLAKE     │
                    │                     │
                    │        RAW          │
                    │  FUEL_PRICES_JSON   │
                    └──────────┬──────────┘
                               │
                               │ Stored Procedure
                               ▼
                    ┌─────────────────────┐
                    │       SILVER        │
                    │                     │
                    │ DIM_STATION         │
                    │ FCT_PRICE_SNAPSHOT  │
                    │ ETL_LOG             │
                    └──────────┬──────────┘
                               │
                               │ MERGE
                               ▼
                    ┌─────────────────────┐
                    │        GOLD         │
                    │                     │
                    │ DIM_STATION         │
                    │ DIM_PRODUCT         │
                    │ DIM_DATETIME        │
                    │ FACT_FUEL_PRICE     │
                    └──────────┬──────────┘
                               │
                               │
                               ▼
                    ┌─────────────────────┐
                    │      POWER BI       │
                    │                     │
                    │ Mapa                │
                    │ Evolución temporal  │
                    │ Comparativa         │
                    │ territorial         │
                    └─────────────────────┘
```

## Flujo de datos

El funcionamiento completo del sistema es:

1. La API del Ministerio proporciona información sobre las estaciones y sus precios.
2. Un script desarrollado en Python realiza la consulta.
3. GitHub Actions ejecuta automáticamente el script cada 3 horas.
4. La respuesta completa de la API se almacena en la capa RAW.
5. RAW utiliza una estrategia **append-only**, conservando las diferentes capturas.
6. Una Stored Procedure de Snowflake transforma los datos de RAW y actualiza SILVER.
7. La misma Stored Procedure actualiza posteriormente las tablas de GOLD.
8. Una Snowflake Task ejecuta automáticamente la Stored Procedure cada 3 horas.
9. Power BI consume las tablas de GOLD para realizar el análisis y la visualización.

---

# 3. Fuentes de datos

La fuente principal de información es la **API de Precios de Carburantes del Ministerio**.

La API proporciona información de las estaciones de servicio y los precios publicados para los diferentes carburantes.

Entre los datos disponibles se encuentran:

- Identificador de estación (`IDEESS`).
- Rótulo.
- Dirección.
- Municipio.
- Provincia.
- Comunidad Autónoma.
- Latitud.
- Longitud.
- Precio de Gasóleo A.
- Precio de Gasolina 95.
- Precio de AdBlue.

La respuesta se recibe en formato JSON.

---

# 4. Capa RAW

La capa RAW contiene las respuestas originales obtenidas de la API.

Tabla:

```text
FUEL_PRICES.RAW.FUEL_PRICES_JSON
```

La información se almacena conservando el JSON original de cada consulta.

Entre los principales campos se encuentran:

```text
INGESTION_ID
INGESTION_TS
PAYLOAD
```

## Estrategia append-only

RAW utiliza una estrategia **append-only**.

Cada nueva ejecución del proceso añade una nueva captura:

```text
Captura 1
Captura 2
Captura 3
...
Captura N
```

Las capturas anteriores no se sobrescriben.

Esto permite:

- Mantener el histórico completo.
- Reconstruir el estado de los precios en un momento determinado.
- Analizar la evolución temporal.
- Detectar cuándo se producen cambios de precio.

---

# 5. Capa SILVER

La capa SILVER transforma el JSON de RAW en información estructurada.

Está formada principalmente por tres tablas.

```text
FUEL_PRICES.SILVER
│
├── DIM_STATION
├── FCT_PRICE_SNAPSHOT
└── ETL_LOG
```

---

## 5.1 DIM_STATION

Tabla:

```text
FUEL_PRICES.SILVER.DIM_STATION
```

Contiene la información descriptiva de las estaciones.

Campos principales:

```text
IDEESS
ROTULO
DIRECCION
MUNICIPIO
PROVINCIA
CCAA
LAT
LON
```

`IDEESS` se utiliza como identificador de la estación.

Las estaciones nuevas se incorporan mediante una comprobación `NOT EXISTS`, evitando duplicados.

---

## 5.2 FCT_PRICE_SNAPSHOT

Tabla:

```text
FUEL_PRICES.SILVER.FCT_PRICE_SNAPSHOT
```

Contiene el histórico de precios obtenido en cada captura.

Campos:

```text
INGESTION_TS
IDEESS
PRODUCT
PRICE_EUR_L
```

Los productos considerados son:

- Gasóleo A.
- Gasolina 95.
- AdBlue.

Los valores procedentes de la API se transforman a formato numérico antes de almacenarse.

Los precios que no son válidos o que vienen vacíos no se incorporan al histórico.

### Idempotencia

Para evitar duplicados, la carga comprueba que no exista previamente la combinación:

```text
INGESTION_TS + IDEESS + PRODUCT
```

De esta forma, una misma captura puede procesarse nuevamente sin generar registros duplicados.

---

## 5.3 ETL_LOG

Tabla:

```text
FUEL_PRICES.SILVER.ETL_LOG
```

Se utiliza para mantener la trazabilidad de las ejecuciones.

Se registra:

```text
INGESTION_TS
RAW_COUNT
SILVER_COUNT
GOLD_COUNT
STATUS
MESSAGE
```

Los estados principales son:

```text
SUCCESS
ERROR
```

Esto permite conocer si una ejecución terminó correctamente y cuántos registros había en cada capa.

---

# 6. Capa GOLD

La capa GOLD contiene el modelo dimensional que utiliza Power BI.

```text
FUEL_PRICES.GOLD
│
├── DIM_STATION
├── DIM_PRODUCT
├── DIM_DATETIME
└── FACT_FUEL_PRICE
```

---

## 6.1 DIM_STATION

Contiene la dimensión de estaciones.

Campos principales:

```text
STATION_KEY
IDEESS
ROTULO
DIRECCION
MUNICIPIO
PROVINCIA
CCAA
LAT
LON
```

La clave dimensional `STATION_KEY` se obtiene mediante un hash del identificador `IDEESS`.

---

## 6.2 DIM_PRODUCT

Contiene los diferentes carburantes analizados.

```text
PRODUCT_KEY
PRODUCT
```

Correspondencia:

| PRODUCT_KEY | PRODUCT |
|---:|---|
| 1 | Gasoleo A |
| 2 | Gasolina 95 |
| 3 | AdBlue |

---

## 6.3 DIM_DATETIME

Contiene la dimensión temporal.

Campos:

```text
DATETIME_KEY
INGESTION_TS
FECHA
HORA
DIA
MES
ANO
```

Cada timestamp de ingesta queda representado en esta dimensión.

Esta tabla permite realizar el análisis temporal de los precios.

---

## 6.4 FACT_FUEL_PRICE

Tabla de hechos principal:

```text
FUEL_PRICES.GOLD.FACT_FUEL_PRICE
```

Relaciona:

```text
Estación
Producto
Momento de la captura
Precio
```

Campos principales:

```text
STATION_KEY
PRODUCT_KEY
DATETIME_KEY
IDEESS
INGESTION_TS
PRICE_EUR_L
```

Esta tabla constituye la principal fuente de datos utilizada por Power BI.

---

# 7. Automatización

La actualización automática está dividida en dos procesos.

```text
              API
               │
               ▼
        GitHub Actions
               │
               ▼
             RAW
               │
               ▼
       Snowflake Task
               │
               ▼
        Stored Procedure
               │
          ┌────┴────┐
          ▼         ▼
       SILVER     GOLD
```

---

## 7.1 Ingesta API → RAW

GitHub Actions ejecuta periódicamente el script Python encargado de consultar la API.

La frecuencia configurada es:

```text
Cada 3 horas
```

Cada ejecución genera una nueva captura en RAW.

Por tanto:

```text
API → Python → GitHub Actions → RAW
```

---

## 7.2 Actualización SILVER → GOLD

Snowflake se encarga posteriormente de procesar la nueva información.

La Stored Procedure utilizada es:

```text
FUEL_PRICES.SILVER.REFRESH_FUEL_DATA()
```

La Snowflake Task asociada es:

```text
FUEL_PRICES.SILVER.TASK_REFRESH_FUEL_DATA
```

Configuración:

```sql
CREATE OR REPLACE TASK FUEL_PRICES.SILVER.TASK_REFRESH_FUEL_DATA
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '3 HOURS'
AS
    CALL FUEL_PRICES.SILVER.REFRESH_FUEL_DATA();

ALTER TASK FUEL_PRICES.SILVER.TASK_REFRESH_FUEL_DATA RESUME;
```

Una vez activada mediante `RESUME`, Snowflake ejecuta automáticamente la procedure cada 3 horas.

---

# 8. Stored Procedure

La procedure principal es:

```text
FUEL_PRICES.SILVER.REFRESH_FUEL_DATA()
```

Su responsabilidad es actualizar las capas SILVER y GOLD después de cada ingesta.

El flujo interno es:

```text
1. Obtener timestamp de la última ingesta
                ↓
2. Actualizar SILVER.DIM_STATION
                ↓
3. Actualizar SILVER.FCT_PRICE_SNAPSHOT
                ↓
4. Actualizar GOLD.DIM_STATION
                ↓
5. Actualizar GOLD.DIM_PRODUCT
                ↓
6. Actualizar GOLD.DIM_DATETIME
                ↓
7. Actualizar GOLD.FACT_FUEL_PRICE
                ↓
8. Registrar trazabilidad
```

Las operaciones de GOLD utilizan `MERGE` para insertar nuevos registros y actualizar aquellos que ya existen.

La procedure también dispone de control de excepciones para registrar ejecuciones fallidas en `ETL_LOG`.

---

# 9. Ejecución manual

La Stored Procedure puede ejecutarse manualmente con:

```sql
CALL FUEL_PRICES.SILVER.REFRESH_FUEL_DATA();
```

Esto permite comprobar que el proceso de transformación funciona correctamente antes de depender de la ejecución automática.

También se puede ejecutar manualmente la Task:

```sql
EXECUTE TASK FUEL_PRICES.SILVER.TASK_REFRESH_FUEL_DATA;
```

La ejecución manual resulta especialmente útil durante las pruebas y la puesta en marcha del sistema.

---

# 10. Pasos de ejecución

## Paso 1. Crear la estructura de Snowflake

Crear la base de datos y los esquemas:

```text
FUEL_PRICES
├── RAW
├── SILVER
└── GOLD
```

Crear también el warehouse utilizado por las tareas:

```text
COMPUTE_WH
```

---

## Paso 2. Crear RAW

Crear:

```text
FUEL_PRICES.RAW.FUEL_PRICES_JSON
```

Esta tabla almacenará las respuestas originales de la API.

---

## Paso 3. Configurar el script Python

El script de ingesta realiza:

1. Consulta de la API.
2. Obtención de la respuesta JSON.
3. Generación del timestamp de ingesta.
4. Conexión con Snowflake.
5. Inserción de la respuesta en RAW.

Las credenciales de Snowflake deben mantenerse como variables de entorno o secrets y no incluirse directamente en el código fuente.

---

## Paso 4. Configurar GitHub Actions

Configurar los secrets necesarios para que GitHub Actions pueda conectarse a Snowflake.

El workflow debe ejecutar el script de Python cada 3 horas.

Resultado:

```text
API
 ↓
Python
 ↓
GitHub Actions
 ↓
RAW
```

---

## Paso 5. Crear SILVER

Crear las tablas:

```text
SILVER.DIM_STATION
SILVER.FCT_PRICE_SNAPSHOT
SILVER.ETL_LOG
```

---

## Paso 6. Crear GOLD

Crear las tablas:

```text
GOLD.DIM_STATION
GOLD.DIM_PRODUCT
GOLD.DIM_DATETIME
GOLD.FACT_FUEL_PRICE
```

---

## Paso 7. Crear la Stored Procedure

Crear:

```text
FUEL_PRICES.SILVER.REFRESH_FUEL_DATA()
```

Probarla manualmente:

```sql
CALL FUEL_PRICES.SILVER.REFRESH_FUEL_DATA();
```

Comprobar que las tablas SILVER y GOLD se actualizan correctamente.

---

## Paso 8. Crear y activar la Task

Crear la Task:

```sql
CREATE OR REPLACE TASK FUEL_PRICES.SILVER.TASK_REFRESH_FUEL_DATA
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '3 HOURS'
AS
    CALL FUEL_PRICES.SILVER.REFRESH_FUEL_DATA();
```

Activarla:

```sql
ALTER TASK FUEL_PRICES.SILVER.TASK_REFRESH_FUEL_DATA RESUME;
```

A partir de este momento, Snowflake ejecutará automáticamente la actualización cada 3 horas.

---

# 11. Trazabilidad

La solución incorpora trazabilidad mínima de las ejecuciones.

Para consultar el histórico de ejecuciones:

```sql
SELECT *
FROM FUEL_PRICES.SILVER.ETL_LOG
ORDER BY INGESTION_TS DESC;
```

También pueden comprobarse los registros de cada capa:

```sql
SELECT
    COUNT(*) AS RAW_COUNT,
    MAX(INGESTION_TS) AS LAST_INGESTION
FROM FUEL_PRICES.RAW.FUEL_PRICES_JSON;
```

```sql
SELECT
    COUNT(*) AS SILVER_COUNT,
    MAX(INGESTION_TS) AS LAST_INGESTION
FROM FUEL_PRICES.SILVER.FCT_PRICE_SNAPSHOT;
```

```sql
SELECT
    COUNT(*) AS GOLD_COUNT,
    MAX(INGESTION_TS) AS LAST_INGESTION
FROM FUEL_PRICES.GOLD.FACT_FUEL_PRICE;
```

De esta forma se puede comprobar tanto la última ingesta como el volumen de información existente en cada capa.

---

# 12. Modelo analítico

El modelo GOLD sigue un esquema dimensional basado en una tabla de hechos y varias dimensiones.

```text
                   DIM_STATION
                        │
                        │
                        ▼
                   ┌───────────┐
                   │           │
DIM_PRODUCT ───────│   FACT    │────── DIM_DATETIME
                   │   FUEL    │
                   │   PRICE   │
                   │           │
                   └───────────┘
```

La tabla de hechos contiene los precios y las claves que permiten relacionarlos con:

- La estación.
- El carburante.
- El momento de la captura.

Esto facilita la explotación de la información desde Power BI.

---

# 13. Informe Power BI

El informe se divide en tres páginas principales:

```text
1. Mapa
2. Evolución temporal
3. Comparativa territorial
```

Las páginas permiten analizar los precios desde tres perspectivas:

- **Geográfica**
- **Temporal**
- **Territorial**

---

# 14. Página 1 — Mapa

La primera página muestra las estaciones de servicio sobre un mapa de España.

Cada estación se representa mediante sus coordenadas:

```text
LAT
LON
```

El color de cada estación depende de su precio actual.

La escala utilizada permite identificar rápidamente las estaciones más baratas y más caras:

```text
🟢 Verde  → estaciones más baratas
🟡        → precios intermedios
🔴 Rojo   → estaciones más caras
```

La página dispone además de filtros para seleccionar el carburante y limitar el análisis a una determinada zona.

## Drill-through

Desde el mapa es posible seleccionar una estación concreta mediante clic derecho y acceder a la página de **Evolución temporal**.

El identificador de estación permite conservar el contexto de la estación seleccionada.

El flujo es:

```text
Mapa
  ↓
Seleccionar estación
  ↓
Clic derecho
  ↓
Drill-through
  ↓
Evolución temporal
  ↓
Histórico de esa estación
```

Esto permite pasar de una visión general de España a un análisis detallado de una estación concreta.

---

# 15. Página 2 — Evolución temporal

La segunda página está orientada al análisis histórico del precio de un carburante.

Incluye dos gráficos principales.

## Evolución del precio

Un gráfico de líneas muestra cómo evoluciona el precio a lo largo del tiempo.

Permite identificar:

- Tendencias ascendentes.
- Tendencias descendentes.
- Periodos de estabilidad.
- Cambios de precio.
- Momentos concretos en los que se producen variaciones.

---

## Variación del precio

El segundo gráfico muestra mediante barras la variación del precio entre capturas consecutivas.

Permite identificar visualmente:

- Incrementos de precio.
- Reducciones de precio.
- Momentos sin variación.
- Magnitud de los cambios.

La combinación de ambos gráficos permite analizar simultáneamente:

```text
Precio absoluto
      +
Variación
      ↓
Comportamiento histórico del precio
```

La página también incorpora filtros de carburante, provincia, municipio, rótulo e intervalo temporal.

Cuando se accede mediante drill-through desde el mapa, el análisis queda contextualizado para la estación seleccionada.

---

# 16. Página 3 — Comparativa territorial

La tercera página permite comparar los precios desde diferentes perspectivas territoriales y comerciales.

Incluye tres rankings.

## Ranking por provincia

Muestra los precios correspondientes a las diferentes provincias.

Permite identificar las provincias con los precios más bajos y más altos.

---

## Ranking por municipio

Muestra los precios por municipio.

Permite analizar con mayor detalle una zona concreta y localizar los municipios con precios más competitivos.

---

## Ranking por rótulo

Muestra el ranking de precios por operador o rótulo.

Permite comparar el comportamiento de diferentes operadores.

---

## Interacción entre gráficos

Los tres gráficos están configurados para interactuar entre sí.

Al seleccionar un elemento de uno de los rankings, los otros gráficos se filtran automáticamente.

Por ejemplo:

```text
Seleccionar provincia
        ↓
Municipios de esa provincia
        ↓
Rótulos presentes en la zona
```

También puede realizarse el análisis comenzando por un municipio o por un rótulo.

Esto permite realizar un análisis progresivo para localizar los precios más competitivos dentro de una determinada zona u operador.

---

# 17. Preguntas que permite responder el sistema

El conjunto de datos y el dashboard permiten responder, entre otras, las siguientes preguntas:

### Evolución temporal

- ¿Cómo ha evolucionado el precio del Gasóleo A en una estación concreta?
- ¿Cómo ha evolucionado el precio de la Gasolina 95?
- ¿Cuándo se produjeron cambios de precio?
- ¿Cuál fue la magnitud de cada cambio?
- ¿Cuál es el comportamiento del precio durante los últimos días?

### Análisis geográfico

- ¿Dónde están las estaciones más baratas?
- ¿Dónde están las estaciones más caras?
- ¿Cuál es el precio actual de una estación concreta?

### Comparativa territorial

- ¿Qué provincias presentan los precios más bajos?
- ¿Qué municipios presentan los precios más competitivos?
- ¿Qué rótulos tienen los precios más bajos?
- ¿Cómo cambia el ranking al seleccionar una determinada provincia?

---

# 18. Tecnologías utilizadas

| Tecnología | Utilización |
|---|---|
| Python | Consulta de la API e ingesta de datos |
| GitHub Actions | Automatización de la ingesta |
| Snowflake | Almacenamiento y procesamiento |
| Snowflake Stored Procedures | Transformación de los datos |
| Snowflake Tasks | Actualización automática cada 3 horas |
| Power BI | Modelado, análisis y visualización |
| API de Precios de Carburantes | Fuente de datos |

---

# 19. Resumen del pipeline

El sistema completo puede resumirse de la siguiente manera:

```text
┌──────────────────────┐
│ API de carburantes   │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Python               │
│ Script de ingesta    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ GitHub Actions       │
│ Ejecución cada 3 h   │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ SNOWFLAKE RAW        │
│ Append-only          │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Stored Procedure     │
│ REFRESH_FUEL_DATA    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ SNOWFLAKE SILVER     │
│ Estaciones           │
│ Snapshots de precios │
│ Trazabilidad         │
└──────────┬───────────┘
           │
           │ MERGE
           ▼
┌──────────────────────┐
│ SNOWFLAKE GOLD       │
│ Dimensiones + hechos │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ POWER BI             │
│                      │
│ Mapa                 │
│ Evolución temporal   │
│ Comparativa territorial│
└──────────────────────┘
```

La solución proporciona así un pipeline completo y automatizado para la **captura, conservación, transformación, trazabilidad y análisis histórico de los precios de carburantes en España**.