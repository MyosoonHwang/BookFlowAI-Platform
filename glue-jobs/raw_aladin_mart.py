"""
raw_aladin_mart · Glue ETL Job
S3 Raw aladin (GZIP NDJSON) → S3 Mart Parquet (SCD Type1 · isbn13  )
Job bookmark enabled →    ·  mart UNION DISTINCT    
"""
import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import Window, functions as F
from pyspark.sql.types import (
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

SOURCE = f"s3://{args['source_bucket']}/aladin/"
TARGET = f"s3://{args['target_bucket']}/aladin_books/"

SCHEMA = StructType([
    StructField("isbn13",      StringType(),  False),
    StructField("title",       StringType(),  True),
    StructField("author",      StringType(),  True),
    StructField("publisher",   StringType(),  True),
    StructField("pub_date",    StringType(),  True),
    StructField("price",       IntegerType(), True),
    StructField("category",    StringType(),  True),
    StructField("cover_url",   StringType(),  True),
    StructField("query_type",  StringType(),  True),
    StructField("category_id", IntegerType(), True),
    StructField("rating",      DoubleType(),  True),
    StructField("synced_at",   StringType(),  True),
])

incoming = (
    spark.read
    .option("compression", "gzip")
    .schema(SCHEMA)
    .json(SOURCE)
    .withColumn("synced_at", F.to_timestamp("synced_at"))
    .filter(F.col("isbn13").isNotNull())
)

#  mart   UNION ·    
try:
    existing = spark.read.parquet(TARGET)
    combined = existing.unionByName(incoming, allowMissingColumns=True)
except Exception:
    combined = incoming

# isbn13   synced_at   (SCD Type1)
window = Window.partitionBy("isbn13").orderBy(F.col("synced_at").desc())
deduped = (
    combined
    .withColumn("_rn", F.row_number().over(window))
    .filter(F.col("_rn") == 1)
    .drop("_rn")
)

(
    deduped.write
    .mode("overwrite")
    .parquet(TARGET)
)

print(f"[raw_aladin_mart] source={SOURCE} target={TARGET} books={deduped.count()}")
job.commit()
