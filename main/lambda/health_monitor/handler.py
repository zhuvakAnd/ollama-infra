import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timezone

import boto3
import psycopg2

METRIC_NAMESPACE = "Ollama/HealthMonitoring"
EMBEDDING_TABLES = ("document_chunk", "document", "knowledge")


def get_db_password():
    client = boto3.client("secretsmanager")
    secret = client.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
    return json.loads(secret["SecretString"])["password"]


def check_alb_health():
    endpoint = os.environ["ALB_ENDPOINT"].rstrip("/")
    request = urllib.request.Request(f"{endpoint}/", method="GET")
    with urllib.request.urlopen(request, timeout=10) as response:
        return response.status == 200


def get_embeddings_count(cursor, connection):
    for table in EMBEDDING_TABLES:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            return int(cursor.fetchone()[0])
        except psycopg2.Error:
            connection.rollback()
    return 0


def get_db_stats():
    connection = psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ.get("DB_NAME", "postgres"),
        user=os.environ.get("DB_USER", "postgres"),
        password=get_db_password(),
        connect_timeout=10,
    )
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT pg_database_size(current_database())")
            db_size = int(cursor.fetchone()[0])

            cursor.execute(
                "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database()"
            )
            connections = int(cursor.fetchone()[0])

            embeddings = get_embeddings_count(cursor, connection)

        return db_size, connections, embeddings
    finally:
        connection.close()


def publish_metrics(alb_healthy, db_size, connections, embeddings):
    timestamp = datetime.now(timezone.utc)
    cloudwatch = boto3.client("cloudwatch")
    cloudwatch.put_metric_data(
        Namespace=METRIC_NAMESPACE,
        MetricData=[
            {
                "MetricName": "ApplicationHealthy",
                "Value": 1 if alb_healthy else 0,
                "Unit": "Count",
                "Timestamp": timestamp,
            },
            {
                "MetricName": "DatabaseSizeBytes",
                "Value": db_size,
                "Unit": "Bytes",
                "Timestamp": timestamp,
            },
            {
                "MetricName": "DatabaseConnections",
                "Value": connections,
                "Unit": "Count",
                "Timestamp": timestamp,
            },
            {
                "MetricName": "EmbeddingsCount",
                "Value": embeddings,
                "Unit": "Count",
                "Timestamp": timestamp,
            },
        ],
    )


def lambda_handler(event, context):
    alb_healthy = False
    try:
        alb_healthy = check_alb_health()
    except (urllib.error.URLError, TimeoutError, ValueError) as error:
        print(f"ALB health check failed: {error}")

    db_size = 0
    connections = 0
    embeddings = 0
    try:
        db_size, connections, embeddings = get_db_stats()
    except Exception as error:
        print(f"Database statistics query failed: {error}")
        raise

    publish_metrics(alb_healthy, db_size, connections, embeddings)

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "alb_healthy": alb_healthy,
                "database_size_bytes": db_size,
                "database_connections": connections,
                "embeddings_count": embeddings,
            }
        ),
    }
