# ETL 파이프라인 · 민지 담당 (Task 6/7/8)

> **담당:** 서민지 | **기간:** 2026-04-30 ~ 2026-05-11

---

## 디렉토리 구조

```
etl/
├── deploy-etl-infra.sh            ← ETL 인프라 한 번에 배포 (base-up + task-data + task-etl-streaming)
├── README.md
│
├── 4_30/                          ← 4/30 (오늘)
│   ├── aladin_api/                  알라딘 API 데이터 수집 (로컬 실행)
│   │   ├── aladin_fetch.py
│   │   ├── requirements.txt
│   │   ├── .env.example             → .env 복사 후 TTBKey 입력
│   │   └── output/                  실행 후 생성 (CSV · ndjson.gz)
│   ├── task6_etl1_pos/              ECS 시뮬레이터 참고 코드
│   │   ├── ecs_online_sim/            온라인 POS 시뮬 (참고용 · 실제 배포는 ecs-sims/)
│   │   ├── ecs_offline_sim/           오프라인 POS 시뮬 (참고용)
│   │   └── ecs_api_client/            외부 판매처 API 클라이언트
│   └── task7_etl2_external/         외부 데이터 수집 Lambda
│       ├── lambda_event_sync/         공휴일/도서행사 수집 (매일 03:00 KST)
│       └── lambda_sns_gen/            SNS 멘션 합성 생성 (10분 cron)
│
├── 5_4/                           ← 5/4
│   ├── task6_etl1_pos/
│   │   └── lambda_pos_ingestor/     Kinesis → RDS sales_realtime + Redis
│   └── verify_e2e_etl1.py           ETL1 E2E 검증 스크립트
│
├── 5_6/                           ← 5/6
│   ├── task7_etl2_external/
│   │   └── lambda_spike_detect/     Z-score 스파이크 감지 (10분 cron)
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

## 배포 / 삭제 스크립트

### 전체 삭제

```bash
bash etl/teardown-etl-infra.sh
```

삭제 순서:
1. `bookflow-cicd-ecs` — CodePipeline + CodeBuild
2. `sam-app` — Lambda 7개
3. `base-down` — Tier 10-99 (VPC / RDS / Redis / Kinesis / ECS)
4. S3 버킷 5개 비우기 + 삭제 (버전 관리 포함)
5. `bookflow-00-s3` CFN 스택

> Tier 00 (KMS / IAM / ECR / Secrets)는 삭제하지 않아 재배포 시 그대로 재사용된다.

### 재배포

```bash
bash etl/deploy-etl-infra.sh
```

S3 버킷이 없으면 자동으로 생성한 뒤 나머지 인프라를 배포한다. teardown 후 바로 실행 가능.

---

## 일정별 할 일

### 4/30 (오늘)

#### 0. ETL 인프라 배포 (최초 1회)

```bash
# Git Bash에서 실행 (BookFlowAI-Platform 루트 기준)
bash etl/deploy-etl-infra.sh
```

배포 순서: Tier 10 VPC 3개 → Tier 20 RDS·Redis·Kinesis → Tier 30 ECS cluster → Tier 40 ECS online/offline-sim

#### 1. 알라딘 API 데이터 수집 `4_30/aladin_api/aladin_fetch.py`

```powershell
cd etl\4_30\aladin_api
py -m pip install -r requirements.txt
copy .env.example .env        # .env 파일 열어서 ALADIN_TTB_KEY 입력

# 로컬 저장만
python aladin_fetch.py

# S3도 업로드
python aladin_fetch.py --upload-s3 --bucket bookflow-raw-354493396671
```

- 출력 파일: `output\aladin_YYYYMMDD_HHMMSS.csv` (검수용 · 우혁에게 전달)
- S3 경로: `s3://bookflow-raw-354493396671/aladin/year=2026/month=04/day=30/`

#### 2. ECS 시뮬레이터 배포

`etl/4_30/task6_etl1_pos/` 파일은 **참고용**입니다.
실제 배포 파일은 `BookFlowAI-Platform/ecs-sims/` 이며 CodePipeline이 자동 빌드합니다.

```powershell
# CodePipeline 배포 (최초 1회)
py scripts\aws\bookflow.py cicd-ecs-up

# 파이프라인 수동 트리거 (BookFlowAI-Apps PR merge 후 자동 안 될 때)
aws codepipeline start-pipeline-execution --name bookflow-cp-ecs --region ap-northeast-1

# ECS 태스크 확인
aws ecs describe-services --cluster bookflow-ecs --services online-sim offline-sim `
  --region ap-northeast-1 `
  --query "services[*].{name:serviceName,running:runningCount,status:status}"
```

#### 3. Lambda 배포 (SAM)

> **⚠️ SAM 배포는 2단계로 나뉜다**
>
> `sam-template.yaml`의 모든 Lambda는 최초 배포 시 `InlineCode`(플레이스홀더)로 되어 있다.
> 이는 인프라 배포 단계와 코드 배포 단계를 분리하기 위한 설계다.
>
> | 단계 | 명령 | 결과 |
> |------|------|------|
> | 1단계 (인프라) | `sam deploy --guided` | VPC, EventBridge 트리거, IAM Role, Kinesis ESM 등 리소스만 생성. Lambda는 플레이스홀더로 동작 (트리거는 받지만 아무것도 안 함) |
> | 2단계 (실제 코드) | `sam build` → `sam deploy` | `lambdas/*/index.py` 실제 코드 + psycopg2 등 외부 라이브러리 패키징 후 Lambda 교체 |
>
> 인프라가 갖춰지기 전에 실제 코드를 올리면 VPC 연결 실패, RDS 접근 불가 에러가 나므로
> 플레이스홀더로 자리를 잡아두고 인프라 완성 후 실제 코드로 교체하는 방식이다.
>
> CloudWatch 로그에서 `placeholder` 문자열이 찍히면 아직 2단계가 안 된 것이다.

```powershell
# 1단계: 인프라 배포 (최초 1회 · deploy-etl-infra.sh 실행 시 이미 완료)
cd C:\Users\campus3S027\MJ_USER\bookflow-azure-iac\bookflow-azure-iac\BookFlowAI-Platform
sam deploy --guided

# 2단계: 실제 코드 배포 (인프라 완성 후 실행)
sam build -t infra\aws\99-serverless\sam-template.yaml
sam deploy
```

---

### 5/4

#### pos-ingestor Lambda `5_4/task6_etl1_pos/lambda_pos_ingestor/index.py`

- Kinesis ESM 트리거 → RDS `sales_realtime` INSERT + `inventory` UPDATE + Redis 무효화
- VPC 내부 실행 · batchItemFailures 패턴

#### ETL1 E2E 검증

```powershell
python etl\5_4\verify_e2e_etl1.py
```

Kinesis 활성 · S3 Raw pos-events 파티션 존재 확인

---

### 5/6

#### spike-detect Lambda `5_6/task7_etl2_external/lambda_spike_detect/index.py`

- 10분 cron
- S3 Raw sns 최근 1시간 → isbn13별 집계 → Poisson Z-score ≥ 3.0 → RDS `spike_events`

#### Glue pos_etl `5_6/task8_etl3_mart/glue_pos_etl/pos_etl.py`

- Raw `pos-events/` (GZIP JSON) → Mart `pos_events/` (Parquet · 파티션: `sale_date`)
- 스키마: `tx_id`, `isbn13`, `qty`, `unit_price`, `total_price`, `channel`, `location_id`, `ts`

```powershell
aws s3 cp etl\5_6\task8_etl3_mart\glue_pos_etl\pos_etl.py `
    s3://bookflow-glue-scripts-354493396671/scripts/pos_etl.py
```

---

### 5/8

#### ETL2 E2E 검증

```powershell
python etl\5_8\task7_etl2_external\verify_e2e_etl2.py
```

S3 Raw 파티션 존재 + Lambda 4개 상태 확인

#### Glue aladin_etl `5_8/task8_etl3_mart/glue_aladin_etl/aladin_etl.py`

- Raw `aladin/` (GZIP NDJSON) → Mart `aladin_books/` (Parquet)
- SCD Type-1: isbn13 기준 최신 `synced_at` 유지

```powershell
aws s3 cp etl\5_8\task8_etl3_mart\glue_aladin_etl\aladin_etl.py `
    s3://bookflow-glue-scripts-354493396671/scripts/aladin_etl.py
```

---

### 5/11

#### Glue event_etl `5_11/task8_etl3_mart/glue_event_etl/event_etl.py`

- Raw `events/{event_type}/` → Mart `calendar_events/` (파티션: `event_type`)
- 4종 UNION: `book_fair`, `holiday`, `publisher_promo`, `author_signing`

#### Glue sns_agg `5_11/task8_etl3_mart/glue_sns_agg/sns_agg.py`

- Raw `sns/` → Mart `sns_mentions/` (파티션: `mention_date`)
- `mention_count ≥ 10` → `is_spike_seed = True`

```powershell
aws s3 cp etl\5_11\task8_etl3_mart\glue_event_etl\event_etl.py `
    s3://bookflow-glue-scripts-354493396671/scripts/event_etl.py
aws s3 cp etl\5_11\task8_etl3_mart\glue_sns_agg\sns_agg.py `
    s3://bookflow-glue-scripts-354493396671/scripts/sns_agg.py
```

---

## 데이터 흐름

```
[알라딘 API]
    └─ aladin_fetch.py (로컬)
       └─ S3 Raw aladin/
          └─ [Glue] aladin_etl.py → Mart aladin_books/ (Parquet)

[공공 API]
    └─ Lambda event-sync (매일 03:00 KST)
       └─ S3 Raw events/
          └─ [Glue] event_etl.py → Mart calendar_events/ (Parquet)

[SNS 합성]
    └─ Lambda sns-gen (10분 cron)
       └─ S3 Raw sns/
          ├─ [Glue] sns_agg.py → Mart sns_mentions/ (Parquet)
          └─ Lambda spike-detect (10분 cron) → RDS spike_events

[ECS 시뮬레이터] ← BookFlowAI-Platform/ecs-sims/ + CodePipeline
    ├─ ECS online-sim  → Kinesis bookflow-pos-events
    └─ ECS offline-sim → Kinesis bookflow-pos-events
          ├─ Firehose → S3 Raw pos-events/
          │    └─ [Glue] pos_etl.py → Mart pos_events/ (Parquet)
          └─ Lambda pos-ingestor → RDS sales_realtime + inventory
                                 → Redis stock:{isbn13}:{loc} 무효화
```

---

## 환경변수 요약

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `ALADIN_TTB_KEY` | 알라딘 API TTBKey | (필수) |
| `RAW_BUCKET` | S3 Raw 버킷명 | `bookflow-raw-354493396671` |
| `KINESIS_STREAM_NAME` | Kinesis 스트림명 | `bookflow-pos-events` |
| `AWS_REGION` | AWS 리전 | `ap-northeast-1` |

---

## 우혁에게 전달할 데이터

알라딘 API 수집 후 생성된 CSV 파일 전달:

```
etl\4_30\aladin_api\output\aladin_20260430_HHMMSS.csv
```

S3에 업로드된 경우 경로 공유:
```
s3://bookflow-raw-354493396671/aladin/year=2026/month=04/day=30/
```
