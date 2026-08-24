# Proyecto 3 - Sistema analítico de precios de carburantes

Sistema de ingesta, almacenamiento y análisis histórico de precios de carburantes de las estaciones de servicio de España.

El proyecto obtiene periódicamente los precios publicados por el Ministerio para la Transición Ecológica y el Reto Demográfico, conserva cada captura histórica y construye un modelo analítico en Snowflake siguiendo una arquitectura por capas **RAW → SILVER → GOLD**.

---

## Objetivo

El objetivo del proyecto es construir un sistema capaz de:

- Obtener periódicamente los precios de carburantes de las estaciones de servicio de España.
- Conservar cada captura de datos para disponer de un histórico.
- Procesar y normalizar la información obtenida.
- Construir un modelo dimensional para análisis.
- Permitir analizar la evolución de los precios a lo largo del tiempo.
- Evitar duplicados mediante procesos de carga idempotentes.
- Automatizar la ingesta mediante GitHub Actions.

Los principales productos analizados son:

- Gasóleo A
- Gasolina 95
- AdBlue

> La API del Ministerio puede no proporcionar precio de AdBlue para determinadas estaciones. En esos casos no se genera un registro de precio para dicha estación y captura.

---

## Arquitectura

```text
                    API Ministerio
                         │
                         │
                         ▼
                GitHub Actions
                         │
                  Ingesta periódica
                         │
                         ▼
                    SNOWFLAKE
                         │
                         ▼
                       RAW
                         │
                 JSON completo
                 + INGESTION_TS
                         │
                         ▼
                      SILVER
                         │
              ┌──────────┴──────────┐
              │                     │
              ▼                     ▼
        DIM_STATION        FCT_PRICE_SNAPSHOT
              │                     │
              └──────────┬──────────┘
                         ▼
                        GOLD
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
 DIM_STATION       DIM_PRODUCT      DIM_DATETIME
        │                │                │
        └────────────────┼────────────────┘
                         ▼
                FACT_FUEL_PRICE