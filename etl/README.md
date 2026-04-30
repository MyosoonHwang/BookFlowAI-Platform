# ETL 파이프라인 · 민지 담당 (Task 6/7/8)

> **담당:** 서민지 | **기간:** 2026-04-30 ~ 2026-05-11

---

## 디렉토리 구조

```
etl/
├── 4_30/                          ← 오늘 (4/30)
│   ├── aladin_api/                  Task7 · 알라딘 API 데이터 수집 (로컬 실행)
│   ├── task6_etl1_pos/              Task6 · ECS 시뮬레이터
│   │   ├── ecs_online_sim/            ECS① 온라인 판매 시뮬
│   │   ├── ecs_offline_sim/           ECS① 오프라인 판매 시뮬
│   │   └── ecs_api_client/            ECS② 외부 판매처 API 클라이언트
│   └── task7_etl2_external/         Task7 · 외부 데이터 수집 Lambda
│       ├── lambda_event_sync/         공휴일/도서행사 수집
│       └── lambda_sns_gen/            SNS 멘션 합성 생성
│
├── 5_4/                           ← 5/4
│   ├── task6_etl1_pos/
│   │   └── lambda_pos_ingestor/     Kinesis → RDS + Redis
│   ├── task7_etl2_external/
│   │   └── lambda_sns_gen/          sns-gen 완료본
│   └── verify_e2e_etl1.py           ETL1 E2E 검증 스크립트
│
├── 5_6/                           ← 5/6
│   ├── task7_etl2_external/
│   │   └── lambda_spike_detect/     Z-score 스파이크 감지
│   └── task8_etl3_mart/
│       └── glue_pos_etl/
│           └── pos_etl.py           POS Raw → Mart Parquet
│
├── 5_8/                           ← 5/8
│   ├── task7_etl2_external/
│   │   └── verify_e2e_etl2.py       ETL2 E2E 검증
│   └── task8_etl3_mart/
│       └── glue_aladin_etl/
│           └── aladin_etl.py        알라딘 Raw → Mart (SCD Type-1)
│
└── 5_11/                          ← 5/11
    └── task8_etl3_mart/
        ├── glue_event_etl/
        │   └── event_etl.py         이벤트 Raw → Mart
        └── glue_sns_agg/
            └── sns_agg.py           SNS 일별 집계 → Mart
```

---

## 일정별 할 일

### 4/30 (오늘)

#### 알라딘 API 데이터 수집 `4_30/aladin_api/aladin_fetch.py`
```bash
cd etl/4_30/aladin_api
pip install -r requirements.txt
cp .env.example .env          # .env에 TTBKey 입력
export ALADIN_TTB_KEY=ttbxxxxxxxx

# 로컬 저장만
python aladin_fetch.py

# S3도 업로드
python aladin_fetch.py --upload-s3 --bucket bookflow-raw-ap-northeast-1
```
- 9개 카테고리 × 최대 4페이지 = 최대 1,800권 수집
- `./output/aladin_YYYYMMDD_HHMMSS.ndjson.gz` — S3 Raw 동일 포맷
- `./output/aladin_YYYYMMDD_HHMMSS.csv` — 검수용

#### ECS 시뮬레이터 (ECR 빌드 + ECS 배포 후 동작)
| 컴포넌트 | 경로 | 역할 |
|---------|------|------|
| ECS① online-sim | `task6_etl1_pos/ecs_online_sim/` | 온라인 POS → Kinesis (10~30초 간격) |
| ECS① offline-sim | `task6_etl1_pos/ecs_offline_sim/` | 오프라인 POS → Kinesis (30~90초 간격) |
| ECS② api-client | `task6_etl1_pos/ecs_api_client/` | 외부 판매처 시뮬 → sales-api 호출 |

#### Lambda (SAM 배포)
| Lambda | 경로 | 트리거 |
|--------|------|--------|
| event-sync | `task7_etl2_external/lambda_event_sync/` | 매일 03:00 KST |
| sns-gen | `task7_etl2_external/lambda_sns_gen/` | 10분마다 cron |

---

### 5/4

#### pos-ingestor Lambda `5_4/task6_etl1_pos/lambda_pos_ingestor/index.py`
- Kinesis ESM 트리거 → RDS `sales_realtime` INSERT + `inventory` UPDATE + Redis 무효화
- VPC 내부 실행 / batchItemFailures 패턴

#### ETL1 E2E 검증
```bash
python etl/5_4/verify_e2e_etl1.py
```
Kinesis 활성, Firehose 활성, S3 Raw pos-events 파티션 확인

---

### 5/6

#### spike-detect Lambda `5_6/task7_etl2_external/lambda_spike_detect/index.py`
- 10분 cron
- S3 Raw sns 최근 1시간 → isbn13별 집계 → Poisson Z-score ≥ 3.0 → RDS `spike_events`

#### Glue pos_etl `5_6/task8_etl3_mart/glue_pos_etl/pos_etl.py`
- Raw `pos-events/` (GZIP JSON) → Mart `pos_events/` (Parquet, 파티션: `sale_date`)
- Args: `JOB_NAME`, `RAW_BUCKET`, `MART_BUCKET`
- 스키마: `tx_id`, `isbn13`, `qty`, `unit_price`, `total_price`, `channel`, `location_id`, `ts`
- `tx_id` 중복 제거, `qty > 0` 필터, isbn13 검증

---

### 5/8

#### ETL2 E2E 검증
```bash
python etl/5_8/task7_etl2_external/verify_e2e_etl2.py
```
S3 Raw 파티션 존재 + Lambda 4개 상태 확인

#### Glue aladin_etl `5_8/task8_etl3_mart/glue_aladin_etl/aladin_etl.py`
- Raw `aladin/` (GZIP NDJSON) → Mart `aladin_books/` (Parquet)
- Args: `JOB_NAME`, `RAW_BUCKET`, `MART_BUCKET`
- 스키마: `isbn13`, `title`, `author`, `publisher`, `pub_date`, `category_id`, `category_name`, `price`, `cover_url`, `sales_point`, `stock_status`, `synced_at`
- SCD Type-1: isbn13 기준 최신 `synced_at` 유지

---

### 5/11

#### Glue event_etl `5_11/task8_etl3_mart/glue_event_etl/event_etl.py`
- Raw `events/{event_type}/` → Mart `calendar_events/` (파티션: `event_type`)
- Args: `JOB_NAME`, `RAW_BUCKET`, `MART_BUCKET`
- 4종 UNION: `book_fair`, `holiday`, `publisher_promo`, `author_signing`
- 스키마: `event_id`, `event_type`, `title`, `start_date`, `end_date`, `event_location`, `isbn13_list`, `synced_at`

#### Glue sns_agg `5_11/task8_etl3_mart/glue_sns_agg/sns_agg.py`
- Raw `sns/` → Mart `sns_mentions/` (파티션: `mention_date`)
- Args: `JOB_NAME`, `RAW_BUCKET`, `MART_BUCKET`
- 스키마: `mention_id`, `isbn13`, `platform`, `mention_count`, `sentiment_score`, `collected_at`
- `mention_count ≥ 10` → `is_spike_seed = True`, `mention_id` 기준 중복 제거

---

## 데이터 흐름

```
[aladin API]
    └─ aladin_fetch.py (로컬/Lambda)
       └─ S3 Raw aladin/
          └─ [Glue] aladin_etl.py → Mart aladin_books/ (Parquet)

[공공 API]
    └─ Lambda event-sync (매일 03:00)
       └─ S3 Raw events/
          └─ [Glue] event_etl.py → Mart calendar_events/ (Parquet)

[SNS 합성]
    └─ Lambda sns-gen (10분 cron)
       └─ S3 Raw sns/
          ├─ [Glue] sns_agg.py → Mart sns_mentions/ (Parquet)
          └─ Lambda spike-detect (10분 cron) → RDS spike_events

[ECS 시뮬레이터]
    ├─ ECS① online-sim
    └─ ECS① offline-sim
       └─ Kinesis bookflow-pos-events
          ├─ Firehose → S3 Raw pos-events/
          │    └─ [Glue] pos_etl.py → Mart pos_events/ (Parquet)
          └─ Lambda pos-ingestor → RDS sales_realtime + inventory
                                 → Redis stock:{isbn13}:{loc} 무효화

[ECS② api-client] → sales-api (API Gateway + Lambda) → 재고 조회
```

---

## 환경변수 요약

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `ALADIN_TTB_KEY` | 알라딘 API TTBKey | (필수) |
| `RAW_BUCKET` | S3 Raw 버킷명 | (필수) |
| `KINESIS_STREAM` | Kinesis 스트림명 | `bookflow-pos-events` |
| `AWS_REGION` | AWS 리전 | `ap-northeast-1` |
| `SALES_API_BASE` | sales-api Gateway URL | (api-client 필수) |
| `SALES_API_KEY` | API Gateway Key | (api-client 필수) |

---

## 배포 방법

### Lambda (SAM)
```bash
cd BookFlowAI-Platform
sam build -t infra/aws/99-serverless/sam-template.yaml
sam deploy --guided
```

### ECS (ECR → ECS)
```bash
# ECR 로그인
aws ecr get-login-password | docker login --username AWS --password-stdin <ACCOUNT>.dkr.ecr.ap-northeast-1.amazonaws.com

# 빌드 & 푸시 (online-sim 예시)
docker build -t bookflow-online-sim etl/4_30/task6_etl1_pos/ecs_online_sim/
docker tag bookflow-online-sim:latest <ECR_URI>/bookflow-online-sim:latest
docker push <ECR_URI>/bookflow-online-sim:latest
```

### Glue
```bash
# S3에 스크립트 업로드
aws s3 cp etl/5_6/task8_etl3_mart/glue_pos_etl/pos_etl.py \
    s3://<SCRIPTS_BUCKET>/glue-jobs/pos_etl.py
```
