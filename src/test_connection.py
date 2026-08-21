import os
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

finally:
    cursor.close()
    conn.close()