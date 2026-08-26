import os
import time
import json
import subprocess
import requests
import snowflake.connector
from datetime import datetime, timezone


# ============================================================
# Configuración
# ============================================================

API_URL = (
    "https://sedeaplicaciones.minetur.gob.es/"
    "ServiciosRESTCarburantes/PreciosCarburantes/"
    "EstacionesTerrestres/"
)


# ============================================================
# Obtener datos de la API
# ============================================================

def get_api_data():
    """
    Descarga los datos de la API del Ministerio.

    Estrategia:
    1. Intenta obtener los datos mediante requests.
    2. Si requests falla, realiza varios reintentos.
    3. Si todos los intentos fallan, utiliza curl como fallback.

    Devuelve:
        dict: JSON de la API convertido a diccionario Python.
    """

    headers = {
        "User-Agent": "Mozilla/5.0",
        "Accept": "application/json",
        "Connection": "close"
    }

    # --------------------------------------------------------
    # Intentos con requests
    # --------------------------------------------------------

    wait_times = [10, 30, 60, 120, 180]

    for attempt, wait_time in enumerate(wait_times, start=1):

        try:
            print(
                f"Intento {attempt}/{len(wait_times)} "
                "de conexión con la API..."
            )

            # Crear una sesión nueva en cada intento
            session = requests.Session()

            response = session.get(
                API_URL,
                headers=headers,
                timeout=(30, 180)
            )

            response.raise_for_status()

            # Convertir respuesta JSON a diccionario Python
            data = response.json()

            print("API consultada correctamente")
            print(f"HTTP status: {response.status_code}")

            return data

        except Exception as e:

            print(
                f"Error en intento {attempt}: "
                f"{type(e).__name__}: {e}"
            )

            if attempt < len(wait_times):

                print(
                    f"Esperando {wait_time} segundos "
                    "antes del siguiente intento..."
                )

                time.sleep(wait_time)

    # --------------------------------------------------------
    # Fallback con curl
    # --------------------------------------------------------

    print("=" * 50)
    print("Todos los intentos con requests han fallado.")
    print("Intentando descargar la API mediante curl...")
    print("=" * 50)

    try:

        result = subprocess.run(
            [
                "curl",
                "-L",
                "--retry", "5",
                "--retry-delay", "10",
                "--retry-all-errors",
                "--connect-timeout", "30",
                "--max-time", "300",
                "-A", "Mozilla/5.0",
                "-H", "Accept: application/json",
                API_URL
            ],
            capture_output=True,
            text=True,
            check=True
        )

        # Convertir respuesta de curl a diccionario Python
        data = json.loads(result.stdout)

        print("API descargada correctamente mediante curl")

        return data

    except Exception as e:

        print("=" * 50)
        print("ERROR: no se ha podido descargar la API.")
        print(f"Detalle: {e}")
        print("=" * 50)

        raise


# ============================================================
# Función principal
# ============================================================

def main():

    # --------------------------------------------------------
    # 1. Obtener identificador de ejecución
    # --------------------------------------------------------

    ingestion_id = os.environ["INGESTION_ID"]

    print("========================================")
    print("INICIO DE INGESTA")
    print("========================================")
    print(f"Ingestion ID: {ingestion_id}")


    # --------------------------------------------------------
    # 2. Consultar API
    # --------------------------------------------------------

    print("Consultando API del Ministerio...")

    # get_api_data() devuelve directamente un diccionario
    data = get_api_data()

    print("JSON recibido correctamente")


    # --------------------------------------------------------
    # 3. Parsear JSON
    # --------------------------------------------------------

    # No usamos data.json() porque data ya es un dict
    payload = data

    print("JSON parseado correctamente")


    # --------------------------------------------------------
    # 4. Validar estructura del JSON
    # --------------------------------------------------------

    if "ListaEESSPrecio" not in payload:

        raise ValueError(
            "La respuesta de la API no contiene "
            "'ListaEESSPrecio'"
        )


    # --------------------------------------------------------
    # 5. Contar estaciones
    # --------------------------------------------------------

    record_count = len(
        payload["ListaEESSPrecio"]
    )

    print(
        f"Estaciones recibidas: {record_count}"
    )


    # --------------------------------------------------------
    # 6. Convertir JSON a texto
    # --------------------------------------------------------

    payload_json = json.dumps(
        payload,
        ensure_ascii=False
    )


    # --------------------------------------------------------
    # 7. Conectar con Snowflake
    # --------------------------------------------------------

    print("Conectando con Snowflake...")

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


        # ----------------------------------------------------
        # 8. Comprobar si la ejecución ya existe
        # ----------------------------------------------------

        print(
            "Comprobando si la ejecución "
            "ya existe en Snowflake..."
        )

        cursor.execute(
            """
            SELECT COUNT(*)
            FROM RAW.FUEL_PRICES_JSON
            WHERE INGESTION_ID = %s
            """,
            (ingestion_id,)
        )

        already_exists = cursor.fetchone()[0]


        # ----------------------------------------------------
        # 9. Evitar duplicados
        # ----------------------------------------------------

        if already_exists > 0:

            print(
                f"La ejecución {ingestion_id} "
                "ya existe en Snowflake."
            )

            print(
                "No se insertarán datos duplicados."
            )

            return


        # ----------------------------------------------------
        # 10. Insertar JSON completo en RAW
        # ----------------------------------------------------

        print(
            "Insertando JSON completo en Snowflake..."
        )

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


        # ----------------------------------------------------
        # 11. Confirmar transacción
        # ----------------------------------------------------

        conn.commit()

        print(
            "JSON completo insertado "
            "correctamente en Snowflake."
        )

        print(
            f"Registros de estaciones: {record_count}"
        )


    finally:

        cursor.close()
        conn.close()


    # --------------------------------------------------------
    # 12. Fin
    # --------------------------------------------------------

    print("========================================")
    print("INGESTA FINALIZADA CORRECTAMENTE")
    print("========================================")


# ============================================================
# Entry point
# ============================================================

if __name__ == "__main__":
    main()
