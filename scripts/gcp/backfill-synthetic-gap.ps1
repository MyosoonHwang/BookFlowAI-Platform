param(
    [string] $ProjectId = $env:BOOKFLOW_GCP_PROJECT_ID,
    [string] $DatasetId = $env:BOOKFLOW_BQ_DATASET,
    [string] $StartDate = "",
    [string] $EndDate = "",
    [int] $AladinCheckCount = 3
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectId)) {
    throw "ProjectId is required. Pass -ProjectId or set BOOKFLOW_GCP_PROJECT_ID."
}
if ([string]::IsNullOrWhiteSpace($DatasetId)) {
    throw "DatasetId is required. Pass -DatasetId or set BOOKFLOW_BQ_DATASET."
}

if ([string]::IsNullOrWhiteSpace($EndDate)) {
    $EndDate = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
}

if ([string]::IsNullOrWhiteSpace($StartDate)) {
    $MaxDateSql = @"
SELECT CAST(DATE_ADD(MAX(feature_date), INTERVAL 1 DAY) AS STRING) AS start_date
FROM ``$ProjectId.$DatasetId.training_dataset``
"@
    $StartDate = (($MaxDateSql | bq query --quiet --use_legacy_sql=false --format=csv) | Select-Object -Last 1).Trim()
}

if ([datetime]::Parse($StartDate) -gt [datetime]::Parse($EndDate)) {
    Write-Host "No backfill needed. StartDate=$StartDate EndDate=$EndDate"
    exit 0
}

if (-not [string]::IsNullOrWhiteSpace($env:ALADIN_TTB_KEY) -and $AladinCheckCount -gt 0) {
    $env:PYTHONIOENCODING = "utf-8"
    @"
import os
import httpx

params = {
    "ttbkey": os.environ["ALADIN_TTB_KEY"],
    "QueryType": "ItemNewAll",
    "MaxResults": $AladinCheckCount,
    "Start": 1,
    "SearchTarget": "Book",
    "Output": "js",
    "Version": "20131101",
}
response = httpx.get("https://www.aladin.co.kr/ttb/api/ItemList.aspx", params=params, timeout=20)
response.raise_for_status()
items = response.json().get("item", [])
print(f"ALADIN_CHECK_OK items={len(items)}")
for item in items:
    print(f"{item.get('isbn13','')} {item.get('title','')[:80]}")
"@ | python -
}

$Sql = @"
DECLARE start_date DATE DEFAULT DATE '$StartDate';
DECLARE end_date DATE DEFAULT DATE '$EndDate';

DELETE FROM ``$ProjectId.$DatasetId.sales_fact``
WHERE SAFE_CAST(sale_date AS DATE) BETWEEN start_date AND end_date;

DELETE FROM ``$ProjectId.$DatasetId.inventory_daily``
WHERE snapshot_date BETWEEN start_date AND end_date;

DELETE FROM ``$ProjectId.$DatasetId.features``
WHERE feature_date BETWEEN start_date AND end_date;

CREATE TABLE IF NOT EXISTS ``$ProjectId.$DatasetId.training_dataset_store`` (
  feature_date DATE,
  isbn13 STRING,
  store_id INT64,
  wh_id INT64,
  channel STRING,
  location_type STRING,
  store_size STRING,
  region STRING,
  qty_sold FLOAT64,
  on_hand FLOAT64,
  reserved_qty FLOAT64,
  safety_stock FLOAT64,
  holiday_flag INT64,
  day_of_week INT64,
  month INT64,
  weekend_flag INT64,
  event_nearby_days INT64,
  sns_mentions_1d INT64,
  sns_mentions_7d INT64,
  book_age_days INT64,
  days_since_last_stockout INT64,
  category_id INT64,
  price_tier STRING,
  sales_point INT64,
  bestseller_flag INT64,
  author_experience_years INT64,
  qty_lag_1 FLOAT64,
  qty_lag_7 FLOAT64,
  qty_rolling_7d FLOAT64,
  qty_rolling_28d FLOAT64,
  demand_segment STRING
);

DELETE FROM ``$ProjectId.$DatasetId.training_dataset``
WHERE feature_date BETWEEN start_date AND end_date;

DELETE FROM ``$ProjectId.$DatasetId.training_dataset_store``
WHERE feature_date BETWEEN start_date AND end_date;

INSERT INTO ``$ProjectId.$DatasetId.features`` (
  feature_date,
  isbn13,
  is_holiday,
  holiday_name,
  season,
  day_of_week,
  is_weekend,
  month,
  event_nearby_days,
  sns_mentions_1d,
  sns_mentions_7d,
  book_age_days,
  is_bestseller_flag,
  on_hand_total,
  days_since_last_stockout
)
WITH dates AS (
  SELECT day AS feature_date
  FROM UNNEST(GENERATE_DATE_ARRAY(start_date, end_date)) AS day
),
books AS (
  SELECT
    isbn13,
    IFNULL(sales_point, 0) AS sales_point,
    IFNULL(is_bestseller_flag, FALSE) AS is_bestseller_flag
  FROM ``$ProjectId.$DatasetId.books_static``
)
SELECT
  d.feature_date,
  b.isbn13,
  d.feature_date IN (DATE '2026-05-05', DATE '2026-05-15', DATE '2026-06-06') AS is_holiday,
  CASE
    WHEN d.feature_date = DATE '2026-05-05' THEN 'Children Day'
    WHEN d.feature_date = DATE '2026-05-15' THEN 'Buddha Birthday'
    WHEN d.feature_date = DATE '2026-06-06' THEN 'Memorial Day'
    ELSE ''
  END AS holiday_name,
  CASE
    WHEN EXTRACT(MONTH FROM d.feature_date) IN (3, 4, 5) THEN 'SPRING'
    WHEN EXTRACT(MONTH FROM d.feature_date) IN (6, 7, 8) THEN 'SUMMER'
    WHEN EXTRACT(MONTH FROM d.feature_date) IN (9, 10, 11) THEN 'FALL'
    ELSE 'WINTER'
  END AS season,
  EXTRACT(DAYOFWEEK FROM d.feature_date) AS day_of_week,
  EXTRACT(DAYOFWEEK FROM d.feature_date) IN (1, 7) AS is_weekend,
  EXTRACT(MONTH FROM d.feature_date) AS month,
  CASE
    WHEN d.feature_date <= DATE '2026-05-05' THEN DATE_DIFF(DATE '2026-05-05', d.feature_date, DAY)
    WHEN d.feature_date <= DATE '2026-05-15' THEN DATE_DIFF(DATE '2026-05-15', d.feature_date, DAY)
    ELSE 30
  END AS event_nearby_days,
  CAST(15 + MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, CAST(d.feature_date AS STRING), 'sns1'))), 80)
    + IF(b.is_bestseller_flag, 80, 0)
    + IF(MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, CAST(DATE_SUB(d.feature_date, INTERVAL 1 DAY) AS STRING), 'sale'))), 10000) < 1700, 90, 0)
    + IF(MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, CAST(DATE_SUB(d.feature_date, INTERVAL 1 DAY) AS STRING), 'spike'))), 100) < 4, 700, 0)
    AS INT64) AS sns_mentions_1d,
  CAST(120 + MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, CAST(d.feature_date AS STRING), 'sns7'))), 350)
    + IF(b.is_bestseller_flag, 400, 0)
    + IF(MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, CAST(DATE_SUB(d.feature_date, INTERVAL 1 DAY) AS STRING), 'spike'))), 100) < 4, 1200, 0)
    AS INT64) AS sns_mentions_7d,
  30 + MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, 'age'))), 1800) AS book_age_days,
  b.is_bestseller_flag,
  80 + MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, CAST(d.feature_date AS STRING), 'stock-total'))), 5000) AS on_hand_total,
  MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, CAST(d.feature_date AS STRING), 'stockout'))), 365) AS days_since_last_stockout
FROM dates d
CROSS JOIN books b;

INSERT INTO ``$ProjectId.$DatasetId.inventory_daily`` (
  snapshot_date,
  isbn13,
  location_id,
  on_hand,
  reserved_qty,
  safety_stock
)
WITH dates AS (
  SELECT day AS snapshot_date
  FROM UNNEST(GENERATE_DATE_ARRAY(start_date, end_date)) AS day
),
books AS (
  SELECT isbn13, IFNULL(is_bestseller_flag, FALSE) AS is_bestseller_flag
  FROM ``$ProjectId.$DatasetId.books_static``
),
locations AS (
  SELECT location_id, IFNULL(size, 'M') AS size
  FROM ``$ProjectId.$DatasetId.locations_static``
  WHERE location_id BETWEEN 1 AND 12
)
SELECT
  d.snapshot_date,
  b.isbn13,
  l.location_id,
  CAST(
    20
    + IF(b.is_bestseller_flag, 60, 0)
    + CASE l.size WHEN 'L' THEN 80 WHEN 'M' THEN 40 ELSE 15 END
    + MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, CAST(l.location_id AS STRING), CAST(d.snapshot_date AS STRING), 'onhand'))), 160)
    AS INT64
  ) AS on_hand,
  CAST(MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, CAST(l.location_id AS STRING), CAST(d.snapshot_date AS STRING), 'reserved'))), 12) AS INT64) AS reserved_qty,
  CAST(CASE l.size WHEN 'L' THEN 15 WHEN 'M' THEN 10 ELSE 5 END AS INT64) AS safety_stock
FROM dates d
CROSS JOIN books b
CROSS JOIN locations l;

INSERT INTO ``$ProjectId.$DatasetId.sales_fact`` (
  sale_date,
  isbn13,
  store_id,
  wh_id,
  channel,
  qty_sold,
  revenue,
  avg_price,
  tx_count
)
WITH dates AS (
  SELECT day AS sale_day
  FROM UNNEST(GENERATE_DATE_ARRAY(start_date, end_date)) AS day
),
books AS (
  SELECT
    isbn13,
    IFNULL(price_sales, 15000) AS price_sales,
    IFNULL(sales_point, 0) AS sales_point,
    IFNULL(is_bestseller_flag, FALSE) AS is_bestseller_flag,
    IFNULL(is_bestseller_flag, FALSE)
      OR MOD(ABS(FARM_FINGERPRINT(CONCAT(isbn13, 'popular-seed'))), 100) < 10 AS is_popular
  FROM ``$ProjectId.$DatasetId.books_static``
),
stores AS (
  SELECT
    location_id AS store_id,
    wh_id,
    IF(location_id BETWEEN 13 AND 14 OR location_type = 'STORE_ONLINE', 'online', 'offline') AS channel,
    IF(location_id BETWEEN 13 AND 14 OR location_type = 'STORE_ONLINE', 'STORE_ONLINE', 'STORE_OFFLINE') AS location_type,
    region,
    IFNULL(size, 'L') AS size,
    location_id BETWEEN 13 AND 14 OR IFNULL(is_virtual, FALSE) AS is_virtual
  FROM ``$ProjectId.$DatasetId.locations_static``
  WHERE location_id BETWEEN 1 AND 14
),
candidates AS (
  SELECT
    d.sale_day,
    b.*,
    s.*,
    MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, CAST(s.store_id AS STRING), CAST(d.sale_day AS STRING), 'sale'))), 10000) AS sale_bucket,
    MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, CAST(s.store_id AS STRING), CAST(d.sale_day AS STRING), 'qty'))), 100) AS qty_bucket,
    MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, CAST(DATE_SUB(d.sale_day, INTERVAL 1 DAY) AS STRING), 'spike'))), 100) AS prior_sns_spike_bucket,
    CAST(
      IF(b.is_popular, 9000, 4200)
      + IF(b.is_bestseller_flag, 1800, 0)
      + CASE s.size WHEN 'L' THEN 500 WHEN 'M' THEN 250 ELSE 0 END
      + IF(s.is_virtual, 700, 0)
      + IF(EXTRACT(DAYOFWEEK FROM d.sale_day) IN (1, 7), 350, 0)
      + IF(d.sale_day BETWEEN DATE '2026-05-03' AND DATE '2026-05-05', 1800, 0)
      + IF(MOD(ABS(FARM_FINGERPRINT(CONCAT(b.isbn13, CAST(DATE_SUB(d.sale_day, INTERVAL 1 DAY) AS STRING), 'spike'))), 100) < 4, 700, 0)
      AS INT64
    ) AS sale_threshold
  FROM dates d
  CROSS JOIN books b
  CROSS JOIN stores s
)
SELECT
  CAST(sale_day AS STRING) AS sale_date,
  isbn13,
  store_id,
  wh_id,
  channel,
  CAST(
    IF(
      is_popular,
      5 + MOD(qty_bucket, 21),
      1 + IF(qty_bucket < 35, 1, 0) + IF(qty_bucket < 8, 1, 0)
    ) AS INT64
  ) AS qty_sold,
  CAST(
    IF(
      is_popular,
      5 + MOD(qty_bucket, 21),
      1 + IF(qty_bucket < 35, 1, 0) + IF(qty_bucket < 8, 1, 0)
    ) * price_sales AS NUMERIC
  ) AS revenue,
  CAST(price_sales AS NUMERIC) AS avg_price,
  CAST(1 AS INT64) AS tx_count
FROM candidates
WHERE sale_bucket < sale_threshold;

INSERT INTO ``$ProjectId.$DatasetId.training_dataset_store`` (
  feature_date,
  isbn13,
  store_id,
  wh_id,
  channel,
  location_type,
  store_size,
  region,
  qty_sold,
  on_hand,
  reserved_qty,
  safety_stock,
  holiday_flag,
  day_of_week,
  month,
  weekend_flag,
  event_nearby_days,
  sns_mentions_1d,
  sns_mentions_7d,
  book_age_days,
  days_since_last_stockout,
  category_id,
  price_tier,
  sales_point,
  bestseller_flag,
  author_experience_years,
  qty_lag_1,
  qty_lag_7,
  qty_rolling_7d,
  qty_rolling_28d,
  demand_segment
)
WITH window_dates AS (
  SELECT day AS feature_date
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(start_date, INTERVAL 28 DAY), end_date)) AS day
),
books AS (
  SELECT
    isbn13,
    category_id,
    price_tier,
    sales_point,
    IF(is_bestseller_flag, 1, 0) AS bestseller_flag,
    author_experience_years
  FROM ``$ProjectId.$DatasetId.books_static``
),
stores AS (
  SELECT
    location_id AS store_id,
    wh_id,
    IF(location_id BETWEEN 13 AND 14 OR location_type = 'STORE_ONLINE', 'online', 'offline') AS channel,
    IF(location_id BETWEEN 13 AND 14 OR location_type = 'STORE_ONLINE', 'STORE_ONLINE', 'STORE_OFFLINE') AS location_type,
    IFNULL(size, 'L') AS store_size,
    region
  FROM ``$ProjectId.$DatasetId.locations_static``
  WHERE location_id BETWEEN 1 AND 14
),
sales AS (
  SELECT
    SAFE_CAST(sale_date AS DATE) AS feature_date,
    isbn13,
    store_id,
    SUM(qty_sold) AS qty_sold
  FROM ``$ProjectId.$DatasetId.sales_fact``
  WHERE SAFE_CAST(sale_date AS DATE) BETWEEN DATE_SUB(start_date, INTERVAL 28 DAY) AND end_date
  GROUP BY feature_date, isbn13, store_id
),
raw AS (
  SELECT
    d.feature_date,
    b.isbn13,
    s.store_id,
    s.wh_id,
    s.channel,
    s.location_type,
    s.store_size,
    s.region,
    CAST(COALESCE(sf.qty_sold, 0) AS FLOAT64) AS qty_sold,
    CAST(COALESCE(i.on_hand, 0) AS FLOAT64) AS on_hand,
    CAST(COALESCE(i.reserved_qty, 0) AS FLOAT64) AS reserved_qty,
    CAST(COALESCE(i.safety_stock, 0) AS FLOAT64) AS safety_stock,
    IF(f.is_holiday, 1, 0) AS holiday_flag,
    f.day_of_week,
    f.month,
    IF(f.is_weekend, 1, 0) AS weekend_flag,
    f.event_nearby_days,
    f.sns_mentions_1d,
    f.sns_mentions_7d,
    f.book_age_days,
    f.days_since_last_stockout,
    b.category_id,
    b.price_tier,
    b.sales_point,
    b.bestseller_flag,
    b.author_experience_years
  FROM window_dates d
  CROSS JOIN books b
  CROSS JOIN stores s
  LEFT JOIN sales sf
    ON d.feature_date = sf.feature_date
    AND b.isbn13 = sf.isbn13
    AND s.store_id = sf.store_id
  LEFT JOIN ``$ProjectId.$DatasetId.inventory_daily`` i
    ON d.feature_date = i.snapshot_date
    AND b.isbn13 = i.isbn13
    AND s.store_id = i.location_id
  LEFT JOIN ``$ProjectId.$DatasetId.features`` f
    ON d.feature_date = f.feature_date
    AND b.isbn13 = f.isbn13
),
scored AS (
  SELECT
    raw.*,
    LAG(qty_sold, 1) OVER (PARTITION BY isbn13, store_id ORDER BY feature_date) AS qty_lag_1,
    LAG(qty_sold, 7) OVER (PARTITION BY isbn13, store_id ORDER BY feature_date) AS qty_lag_7,
    AVG(qty_sold) OVER (
      PARTITION BY isbn13, store_id
      ORDER BY feature_date
      ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS qty_rolling_7d,
    AVG(qty_sold) OVER (
      PARTITION BY isbn13, store_id
      ORDER BY feature_date
      ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
    ) AS qty_rolling_28d,
    SUM(qty_sold) OVER (
      PARTITION BY isbn13, store_id
      ORDER BY feature_date
      ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
    ) AS demand_28d
  FROM raw
)
SELECT
  feature_date,
  isbn13,
  store_id,
  wh_id,
  channel,
  location_type,
  store_size,
  region,
  qty_sold,
  on_hand,
  reserved_qty,
  safety_stock,
  holiday_flag,
  day_of_week,
  month,
  weekend_flag,
  event_nearby_days,
  sns_mentions_1d,
  sns_mentions_7d,
  book_age_days,
  days_since_last_stockout,
  category_id,
  price_tier,
  sales_point,
  bestseller_flag,
  author_experience_years,
  qty_lag_1,
  qty_lag_7,
  qty_rolling_7d,
  qty_rolling_28d,
  CASE
    WHEN demand_28d >= 12 THEN 'high'
    WHEN demand_28d >= 3 THEN 'medium'
    ELSE 'low'
  END AS demand_segment
FROM scored
WHERE feature_date BETWEEN start_date AND end_date;

INSERT INTO ``$ProjectId.$DatasetId.training_dataset`` (
  feature_date,
  isbn13,
  wh_id,
  qty_sold,
  on_hand,
  reserved_qty,
  holiday_flag,
  day_of_week,
  month,
  weekend_flag,
  event_nearby_days,
  sns_mentions_1d,
  sns_mentions_7d,
  book_age_days,
  days_since_last_stockout,
  category_id,
  price_tier,
  sales_point,
  bestseller_flag,
  author_experience_years,
  qty_lag_1,
  qty_lag_7,
  qty_rolling_7d,
  qty_rolling_28d
)
WITH window_dates AS (
  SELECT day AS feature_date
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(start_date, INTERVAL 28 DAY), end_date)) AS day
),
books AS (
  SELECT
    isbn13,
    category_id,
    price_tier,
    sales_point,
    IF(is_bestseller_flag, 1, 0) AS bestseller_flag,
    author_experience_years
  FROM ``$ProjectId.$DatasetId.books_static``
),
warehouses AS (
  SELECT 1 AS wh_id UNION ALL SELECT 2 AS wh_id
),
sales AS (
  SELECT
    SAFE_CAST(sale_date AS DATE) AS feature_date,
    isbn13,
    wh_id,
    SUM(qty_sold) AS qty_sold
  FROM ``$ProjectId.$DatasetId.sales_fact``
  WHERE SAFE_CAST(sale_date AS DATE) BETWEEN DATE_SUB(start_date, INTERVAL 28 DAY) AND end_date
  GROUP BY feature_date, isbn13, wh_id
),
inventory AS (
  SELECT
    i.snapshot_date AS feature_date,
    i.isbn13,
    l.wh_id,
    SUM(i.on_hand) AS on_hand,
    SUM(i.reserved_qty) AS reserved_qty
  FROM ``$ProjectId.$DatasetId.inventory_daily`` i
  JOIN ``$ProjectId.$DatasetId.locations_static`` l
    ON i.location_id = l.location_id
  WHERE i.snapshot_date BETWEEN DATE_SUB(start_date, INTERVAL 28 DAY) AND end_date
  GROUP BY feature_date, isbn13, wh_id
),
raw AS (
  SELECT
    d.feature_date,
    b.isbn13,
    w.wh_id,
    CAST(COALESCE(s.qty_sold, 0) AS FLOAT64) AS qty_sold,
    CAST(COALESCE(i.on_hand, 0) AS FLOAT64) AS on_hand,
    CAST(COALESCE(i.reserved_qty, 0) AS FLOAT64) AS reserved_qty,
    IF(f.is_holiday, 1, 0) AS holiday_flag,
    f.day_of_week,
    f.month,
    IF(f.is_weekend, 1, 0) AS weekend_flag,
    f.event_nearby_days,
    f.sns_mentions_1d,
    f.sns_mentions_7d,
    f.book_age_days,
    f.days_since_last_stockout,
    b.category_id,
    b.price_tier,
    b.sales_point,
    b.bestseller_flag,
    b.author_experience_years
  FROM window_dates d
  CROSS JOIN books b
  CROSS JOIN warehouses w
  LEFT JOIN sales s
    ON d.feature_date = s.feature_date
    AND b.isbn13 = s.isbn13
    AND w.wh_id = s.wh_id
  LEFT JOIN inventory i
    ON d.feature_date = i.feature_date
    AND b.isbn13 = i.isbn13
    AND w.wh_id = i.wh_id
  LEFT JOIN ``$ProjectId.$DatasetId.features`` f
    ON d.feature_date = f.feature_date
    AND b.isbn13 = f.isbn13
),
scored AS (
  SELECT
    raw.*,
    LAG(qty_sold, 1) OVER (PARTITION BY isbn13, wh_id ORDER BY feature_date) AS qty_lag_1,
    LAG(qty_sold, 7) OVER (PARTITION BY isbn13, wh_id ORDER BY feature_date) AS qty_lag_7,
    AVG(qty_sold) OVER (
      PARTITION BY isbn13, wh_id
      ORDER BY feature_date
      ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS qty_rolling_7d,
    AVG(qty_sold) OVER (
      PARTITION BY isbn13, wh_id
      ORDER BY feature_date
      ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
    ) AS qty_rolling_28d
  FROM raw
)
SELECT
  feature_date,
  isbn13,
  wh_id,
  qty_sold,
  on_hand,
  reserved_qty,
  holiday_flag,
  day_of_week,
  month,
  weekend_flag,
  event_nearby_days,
  sns_mentions_1d,
  sns_mentions_7d,
  book_age_days,
  days_since_last_stockout,
  category_id,
  price_tier,
  sales_point,
  bestseller_flag,
  author_experience_years,
  qty_lag_1,
  qty_lag_7,
  qty_rolling_7d,
  qty_rolling_28d
FROM scored
WHERE feature_date BETWEEN start_date AND end_date;
"@

Write-Host "Backfilling $ProjectId.$DatasetId from $StartDate to $EndDate"
$Sql | bq query --quiet --use_legacy_sql=false
Write-Host "Backfill complete."
