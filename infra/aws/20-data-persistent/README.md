# Tier 20 · Data Persistent (⏰ 매일)

## 이 Tier의 역할

**RDS PostgreSQL · ElastiCache Redis · Kinesis Data Stream + Firehose** — Data VPC DB subnet 에 배치.

라이프사이클: ⏰ 매일 · `base-up.ps1` 이 구축 모드로 올림 · `base-down.ps1` 이 저녁에 내림.

## Stack (3개)

| YAML | 내용 | 배치 위치 |
|---|---|---|
| `rds.yaml` | PostgreSQL 16 · db.t3.micro · SubnetGroup + ParameterGroup + SG + Enhanced Monitoring Role | Data VPC DB subnet (10.3.11/12.0/24) |
| `redis.yaml` | Redis 7 · cache.t3.micro · SubnetGroup + SG | Data VPC DB subnet |
| `kinesis.yaml` | pos-events Stream (5 shards) + Firehose → S3 Raw | VPC 무관 (서비스형) |

## 구축 vs 시나리오 모드 (Parameter-driven)

**구축 (base-up 기본값)** — 비용 절감:
- RDS: `EnableMultiAz=false` (Single-AZ)
- Redis: `EnableReplication=false` (CacheCluster · 1 node)

**시나리오 HA (`task-scenario-ha.ps1`)** — failover 테스트용:
- RDS: `EnableMultiAz=true` → in-place modify (약 5-10 분)
- Redis: `EnableReplication=true` → ReplicationGroup 으로 replace (cache 소실 · 2 node Multi-AZ)

Revert: `task-scenario-ha-revert.ps1` 로 구축 모드 복귀.

## 주요 Import (Tier 10 · Tier 00 dependency)

### rds.yaml
- `bookflow-subnet-data-db-az1` / `az2` (from `vpc-data`)
- `bookflow-vpc-data-id` (SG VPC)
- `bookflow-secrets-rds-master-arn` (Master username/password · dynamic reference)

### redis.yaml
- `bookflow-subnet-data-db-az1` / `az2`
- `bookflow-vpc-data-id`

### kinesis.yaml
- `bookflow-s3-raw-name` (Firehose target bucket)

## Security Group (Custom · default 미사용)

| SG | Ingress | 출처 CIDR |
|---|---|---|
| `rds-sg` | tcp/5432 | BookFlow AI 10.0 / Sales Data 10.1 / Egress 10.2 / Ansible 10.4 |
| `redis-sg` | tcp/6379 | BookFlow AI 10.0 (Pod 세션/캐시) |

Firehose는 IAM Role 로만 접근 · SG 불필요.

## 배포 순서 (base-up.ps1)

```
1. rds, redis, kinesis  ← 병렬 가능 · 모두 Tier 10 Import 만 의존
```

RDS 가 가장 오래 걸림 (약 8-12 분). 구축 모드 Single-AZ 라 상대적으로 빠름.

## 다른 Tier 와의 관계

- Tier 10 (network-core): Subnet / VPC Import 만
- Tier 00 (foundation): S3 Raw · Secrets Manager RDS password Import
- Tier 30 (compute-cluster): 이 Tier 의 endpoint 를 Pod 에서 ConfigMap/Secret 으로 주입
- Tier 40 (compute-runtime): POS 시뮬 ECS 가 Kinesis Stream 에 put-record
- Tier 99 (serverless): `bq-load` Lambda 가 Kinesis 소비 · `aladin-sync` 가 RDS insert

## 검증

```powershell
# lint
cfn-lint infra\aws\20-data-persistent\*.yaml

# 배포 후 확인
aws rds describe-db-instances --db-instance-identifier bookflow-postgres --query 'DBInstances[0].{status:DBInstanceStatus,multiaz:MultiAZ,endpoint:Endpoint.Address}'
aws elasticache describe-cache-clusters --cache-cluster-id bookflow-redis --query 'CacheClusters[0].{status:CacheClusterStatus,nodes:NumCacheNodes}'
aws kinesis describe-stream --stream-name bookflow-pos-events --query 'StreamDescription.{status:StreamStatus,shards:length(Shards)}'

# Firehose 흐름 확인
aws firehose describe-delivery-stream --delivery-stream-name bookflow-pos-events-firehose --query 'DeliveryStreamDescription.DeliveryStreamStatus'
```

## 비용 추정 (Tier 20 · 198h × 22d 기준)

| 자원 | 시간당 | 월 비용 |
|---|---|---|
| RDS db.t3.micro Single-AZ | $0.026 | $5.15 |
| RDS db.t3.micro Multi-AZ (시나리오 한정) | $0.052 | 실제로는 몇 시간 · 무시 |
| RDS gp3 20 GB | $0.115/GB-월 | $2.30 |
| ElastiCache cache.t3.micro | $0.026 | $5.15 |
| Kinesis 5 shards | $0.015/shard·h | $14.85 |
| Firehose ingestion | $0.029/GB | 저비용 (데모 수량) |

**합계 예상**: ~$28/월 (구축 모드 기준 · 실제 traffic 추가 별도)

## 비고

- RDS EngineVersion `16.6` 기준 (cfn-lint 경고 없음 · 2026-04 current)
- Parameter Group `log_statement: mod` + `log_min_duration_statement: 1000ms` (감사 대비)
- Firehose 파티션: `pos-events/year=YYYY/month=MM/day=DD/` · GZIP 압축
- `DeletionPolicy: Delete` · `UpdateReplacePolicy: Delete` — 매일 destroy 패턴
- `BackupRetentionPeriod: 0` — Ansible re-seed 라 자동 백업 불필요 (destroy 도 더 빠름)
