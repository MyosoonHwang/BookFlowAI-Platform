"""
raw_event_mart · Glue ETL Job
S3 Raw events (GZIP NDJSON) → S3 Mart Parquet (partitioned by event_type)
 ·  ·  ·  4  ·   (date + event_type + name)
"""
import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import (
    BooleanType,
    DoubleType,
    IntegerType,
    StringType,
    StructField,
    StructType,
)

args = getResolvedOptions(
    sys.argv,
    ["JOB_NAME", "source_bucket", "target_bucket", "catalog_database"],
)

sc    = SparkContext()
glue  = GlueContext(sc)
spark = glue.spark_session
job   = Job(glue)
job.init(args["JOB_NAME"], args)

SOURCE = f"s3://{args['source_bucket']}/events/"
TARGET = f"s3://{args['target_bucket']}/calendar_events/"

SCHEMA = StructType([
    StructField("event_type",    StringType(),  False),
    StructField("date",          StringType(),  True),
    StructField("name",          StringType(),  True),
    StructField("is_holiday",    BooleanType(), True),
    StructField("season_idx",    DoubleType(),  True),
    StructField("duration_days", IntegerType(), True),
    StructField("synced_at",     StringType(),  True),
])

df = (
    spark.read
    .option("compression", "gzip")
    .schema(SCHEMA)
    .json(SOURCE)
    .withColumn("synced_at",  F.to_timestamp("synced_at"))
    .withColumn("event_date", F.to_date("date", "yyyyMMdd"))
    .filter(F.col("event_type").isNotNull() & F.col("date").isNotNull())
    .dropDuplicates(["date", "event_type", "name"])
)

(
    df.write
    .mode("append")
    .partitionBy("event_type")
    .parquet(TARGET)
)

print(f"[raw_event_mart] source={SOURCE} target={TARGET} rows={df.count()}")
job.commit()
