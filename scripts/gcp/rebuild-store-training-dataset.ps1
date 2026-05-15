param(
    [string] $ProjectId = $env:BOOKFLOW_GCP_PROJECT_ID,
    [string] $DatasetId = $env:BOOKFLOW_BQ_DATASET,
    [string] $OutputTable = "training_dataset_store"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectId)) {
    throw "ProjectId is required. Pass -ProjectId or set BOOKFLOW_GCP_PROJECT_ID."
}
if ([string]::IsNullOrWhiteSpace($DatasetId)) {
    throw "DatasetId is required. Pass -DatasetId or set BOOKFLOW_BQ_DATASET."
}

$Sql = @"
CREATE OR REPLACE TABLE ``$ProjectId.$DatasetId.$OutputTable`` AS
WITH date_spine AS (
  SELECT day AS feature_date
  FROM UNNEST(GENERATE_DATE_ARRAY(
    (SELECT MIN(SAFE_CAST(sale_date AS DATE)) FROM ``$ProjectId.$DatasetId.sales_fact``),
    (SELECT MAX(SAFE_CAST(sale_date AS DATE)) FROM ``$ProjectId.$DatasetId.sales_fact``)
  )) AS day
),
books AS (
  SELECT
    isbn13,
    category_id,
    price_tier,
    COALESCE(sales_point, 0) AS sales_point,
    CAST(COALESCE(is_bestseller_flag, FALSE) AS INT64) AS bestseller_flag,
    COALESCE(author_experience_years, 0) AS author_experience_years
  FROM ``$ProjectId.$DatasetId.books_static``
),
stores AS (
  SELECT
    location_id AS store_id,
    wh_id,
    IF(location_id BETWEEN 13 AND 14 OR location_type = 'STORE_ONLINE', 'online', 'offline') AS channel,
    IF(location_id BETWEEN 13 AND 14 OR location_type = 'STORE_ONLINE', 'STORE_ONLINE', 'STORE_OFFLINE') AS location_type,
    COALESCE(size, 'L') AS store_size,
    region
  FROM ``$ProjectId.$DatasetId.locations_static``
  WHERE location_id BETWEEN 1 AND 14
),
sales AS (
  SELECT
    SAFE_CAST(sale_date AS DATE) AS feature_date,
    isbn13,
    store_id,
    SUM(COALESCE(CAST(qty_sold AS FLOAT64), 0)) AS qty_sold
  FROM ``$ProjectId.$DatasetId.sales_fact``
  WHERE SAFE_CAST(sale_date AS DATE) IS NOT NULL
    AND store_id BETWEEN 1 AND 14
  GROUP BY feature_date, isbn13, store_id
),
features_dedup AS (
  SELECT * EXCEPT(row_num)
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY isbn13, feature_date
        ORDER BY feature_date
      ) AS row_num
    FROM ``$ProjectId.$DatasetId.features``
  )
  WHERE row_num = 1
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
    CAST(COALESCE(f.is_holiday, FALSE) AS INT64) AS holiday_flag,
    COALESCE(f.day_of_week, EXTRACT(DAYOFWEEK FROM d.feature_date)) AS day_of_week,
    COALESCE(f.month, EXTRACT(MONTH FROM d.feature_date)) AS month,
    CAST(COALESCE(f.is_weekend, EXTRACT(DAYOFWEEK FROM d.feature_date) IN (1, 7)) AS INT64) AS weekend_flag,
    COALESCE(f.event_nearby_days, 0) AS event_nearby_days,
    COALESCE(f.sns_mentions_1d, 0) AS sns_mentions_1d,
    COALESCE(f.sns_mentions_7d, 0) AS sns_mentions_7d,
    COALESCE(f.book_age_days, 0) AS book_age_days,
    COALESCE(f.days_since_last_stockout, 0) AS days_since_last_stockout,
    b.category_id,
    b.price_tier,
    b.sales_point,
    b.bestseller_flag,
    b.author_experience_years
  FROM date_spine d
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
  LEFT JOIN features_dedup f
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
FROM scored;

SELECT
  COUNT(*) AS row_count,
  COUNT(DISTINCT isbn13) AS isbn_count,
  COUNT(DISTINCT store_id) AS store_count,
  COUNT(DISTINCT CONCAT(isbn13, '#', CAST(store_id AS STRING))) AS series_count,
  MIN(feature_date) AS min_date,
  MAX(feature_date) AS max_date,
  ROUND(AVG(IF(qty_sold = 0, 1, 0)), 4) AS zero_ratio,
  ROUND(AVG(qty_sold), 4) AS avg_qty
FROM ``$ProjectId.$DatasetId.$OutputTable``;
"@

$Sql | bq query --use_legacy_sql=false
