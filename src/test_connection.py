import os
import json
import snowflake.connector


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

    # 1. Comprobar conexión
    cursor.execute("""
        SELECT
            CURRENT_VERSION(),
            CURRENT_USER(),
            CURRENT_ROLE()
    """)

    result = cursor.fetchone()

    print("Conexión correcta con Snowflake")
    print(f"Snowflake version: {result[0]}")
    print(f"User: {result[1]}")
    print(f"Role: {result[2]}")

    # 2. JSON de prueba
    test_payload = {
        "test": True,
        "message": "GitHub Actions -> Snowflake",
        "source": "test"
    }

    # Convertimos el diccionario a JSON
    payload_json = json.dumps(test_payload)

    # 3. Insertar en RAW
    cursor.execute("""
        INSERT INTO RAW.FUEL_PRICES_JSON (
            INGESTION_TS,
            PAYLOAD,
            SOURCE_URL
        )
        SELECT
            CURRENT_TIMESTAMP(),
            PARSE_JSON(%s),
            %s
    """, (
        payload_json,
        "https://test.local"
    ))

    conn.commit()

    print("JSON de prueba insertado correctamente en RAW")

finally:
    cursor.close()
    conn.close()