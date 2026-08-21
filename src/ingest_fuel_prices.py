import os
import json
import requests
import snowflake.connector


API_URL = (
    "https://sedeaplicaciones.minetur.gob.es/"
    "ServiciosRESTCarburantes/PreciosCarburantes/"
    "EstacionesTerrestres/"
)


def main():

    ingestion_id = os.environ["INGESTION_ID"]

    # --------------------------------------------------
    # 1. Consultar API
    # --------------------------------------------------

    print("Consultando API del Ministerio...")

    response = requests.get(
        API_URL,
        headers={
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0"
        },
        timeout=60
    )

    response.raise_for_status()

    print(f"HTTP status: {response.status_code}")

    payload = response.json()

    print("JSON recibido correctamente")

    # Número de estaciones recibidas
    record_count = len(payload["ListaEESSPrecio"])

    print(f"Estaciones recibidas: {record_count}")
    print(f"Ingestion ID: {ingestion_id}")

    # --------------------------------------------------
    # 2. Conectar con Snowflake
    # --------------------------------------------------

    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"],
        warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
        database=os.environ["SNOWFLAKE_DATABASE"],
        schema=os.environ["SNOWFLAKE_SCHEMA"],
    )

    try:

        cursor = conn.cursor()

        # --------------------------------------------------
        # 3. Comprobar si esta ejecución ya existe
        # --------------------------------------------------

        cursor.execute(
            """
            SELECT COUNT(*)
            FROM RAW.FUEL_PRICES_JSON
            WHERE INGESTION_ID = %s
            """,
            (ingestion_id,)
        )

        already_exists = cursor.fetchone()[0]

        if already_exists > 0:

            print(
                f"La ejecución {ingestion_id} ya existe. "
                "No se insertarán datos duplicados."
            )

            return

        # --------------------------------------------------
        # 4. Convertir JSON a texto
        # --------------------------------------------------

        payload_json = json.dumps(
            payload,
            ensure_ascii=False
        )

        # --------------------------------------------------
        # 5. Insertar captura
        # --------------------------------------------------

        cursor.execute(
            """
            INSERT INTO RAW.FUEL_PRICES_JSON (
                INGESTION_ID,
                INGESTION_TS,
                RECORD_COUNT,
                PAYLOAD,
                SOURCE_URL
            )
            SELECT
                %s,
                CURRENT_TIMESTAMP(),
                %s,
                PARSE_JSON(%s),
                %s
            """,
            (
                ingestion_id,
                record_count,
                payload_json,
                API_URL
            )
        )

        conn.commit()

        print(
            f"Captura {ingestion_id} insertada correctamente."
        )

        print(
            f"Registros insertados: {record_count}"
        )

    finally:

        cursor.close()
        conn.close()


if __name__ == "__main__":
    main()