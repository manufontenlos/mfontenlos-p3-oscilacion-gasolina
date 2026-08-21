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

    # --------------------------------------------------
    # 1. Consultar API
    # --------------------------------------------------

    print("Consultando API del Ministerio...")

    response = requests.get(
        API_URL,
        timeout=60
    )

    response.raise_for_status()

    print(f"HTTP status: {response.status_code}")

    payload = response.json()

    print("JSON recibido correctamente")


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
        # 3. Insertar JSON completo en RAW
        # --------------------------------------------------

        payload_json = json.dumps(
            payload,
            ensure_ascii=False
        )

        cursor.execute(
            """
            INSERT INTO RAW.FUEL_PRICES_JSON (
                INGESTION_TS,
                PAYLOAD,
                SOURCE_URL
            )
            SELECT
                CURRENT_TIMESTAMP(),
                PARSE_JSON(%s),
                %s
            """,
            (
                payload_json,
                API_URL
            )
        )

        conn.commit()

        print("JSON completo insertado correctamente en RAW")

    finally:

        cursor.close()
        conn.close()


if __name__ == "__main__":
    main()