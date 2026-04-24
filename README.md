# BookFlowAI-Platform

> BOOKFLOW · 도서 유통 AI 통합 물류·재고 관리 플랫폼
> 인프라 + CI/CD 파이프라인 정의 (변경 적음)
> V6.2 아키텍처 · 도쿄 (ap-northeast-1)

## 관련 레포지토리

| 레포 | 용도 | 변경 빈도 |
|---|---|---|
| **BookFlowAI-Platform** (여기) | 인프라 · CI/CD 정의 | 적음 |
| **bookflow-apps** (별도) | Pod Dockerfile · ECS 시뮬 · Publisher · Glue 스크립트 | 잦음 |

`bookflow-apps` 레포에서 앱 코드를 관리하며, 해당 레포 push 시 이 레포의 CodePipeline/GHA가 자동 트리거됨.

## 디렉토리 구조

```
BookFlowAI-Platform/
├── infra/
│   ├── aws/                      CloudFormation (Tier별 Stack 분리)
│   │   ├── 00-foundation/          🔒 영구 (IAM · KMS · S3 · Secrets · ACM · R53 · CloudTrail · CloudWatch)
│   │   ├── 10-data-persistent/     ⏰ 매일 (RDS · Redis · Kinesis)
│   │   ├── 20-network-daily/       ⏰ 매일 (VPC · Peering · TGW · VPN · Client VPN · NAT · Endpoints · ALB · WAF)
│   │   ├── 30-compute-cluster/     ⏰ 매일 (EKS · ECS · Ansible CN)
│   │   ├── 40-compute-runtime/     ⏰ 매일 (EKS Node · ECS Services · Publisher ASG)
│   │   ├── 99-serverless/          🔒 영구 (SAM · Lambda × 6)
│   │   └── 99-glue/                📆 실행시 (Glue Catalog · Jobs 메타 · Step Functions)
│   │
│   ├── azure/                    Bicep
│   │   ├── 00-foundation/          🔒 영구 (Entra · VNet · Key Vault · Event Grid)
│   │   ├── 20-network-daily/       ⏰ 매일 (VPN Gateway)
│   │   └── 99-content/             🔒 영구 (Logic Apps × 12 · Function App)
│   │
│   └── gcp/                      Terraform
│       ├── 00-foundation/          🔒 영구 (Project · VPC · GCS · BQ · WIF)
│       ├── 20-network-daily/       ⏰ 매일 (HA VPN · Cloud Router · PSC)
│       └── 99-content/             🔒 영구 (Cloud Functions × 3 · Workflows · Vertex)
│
├── cicd/
│   ├── codepipeline/             AWS 네이티브 CI/CD (4 파이프라인)
│   │   ├── eks-pipeline.yaml
│   │   ├── ecs-pipeline.yaml
│   │   ├── lambda-sam-pipeline.yaml
│   │   └── publisher-codedeploy.yaml
│   └── ansible/                  Glue + RDS GitOps
│       ├── playbooks/              glue-deploy · rds-schema · rds-seed · rds-grants
│       ├── roles/                  glue-scripts · postgres-schema
│       └── sql/                    001_tables · 002_indexes · 003_grants
│
├── .github/workflows/            GHA (OIDC/WIF · long-lived secret 0)
│   ├── azure-bicep-deploy.yml      Azure 99-content 배포
│   ├── gcp-terraform-apply.yml     GCP 99-content 배포
│   ├── glue-redeploy.yml           Glue scripts · git push → SSM → CN
│   └── rds-redeploy.yml            RDS schema · git push → SSM → CN
│
├── scripts/                      일상 운영
│   ├── deploy-foundation.sh        Day 0 1회 (00 + 99)
│   ├── start-day.sh                매일 09:00 (10 + 20 + 30 + 40)
│   ├── stop-day.sh                 매일 18:00 (역순 destroy)
│   ├── deploy-aws-only.sh
│   └── deploy-content-only.sh
│
└── docs/                         아키텍처·배포·비용·라이프사이클
    ├── ARCHITECTURE.md
    ├── DEPLOYMENT.md
    ├── COST.md
    └── LIFECYCLE.md
```

## 핵심 원칙

1. **VPC Peering (P1-P2) → TGW (P3-P4) 마이그레이션** — 개발 기간엔 시간당 무료 Peering
2. **NAT Gateway auth-pod 전용** — Lambda는 AWS 관리형이라 NAT 불필요
3. **Interface Endpoint 단일 AZ** (학프 간소화) — 7 endpoints (ECR×2 + Kinesis + SSM + Secrets + CW Logs + KMS)
4. **Client VPN Phase 기반 최소화** — P2 Pod 본격 dev 시 subnet Public 전환
5. **WAF prorated + External ALB만** — Internal ALB(EKS Ingress)는 WAF 불필요
6. **영구 자원 최소화** — 신뢰·비밀·데이터·정체성만 영구
7. **TGW Hub 자체 무과금** — Attachment만 과금

## 도구 분담

| 영역 | 도구 | 이유 |
|---|---|---|
| AWS 인프라 | CloudFormation | AWS 네이티브 · Tier별 독립 stack |
| AWS CI/CD | CodePipeline + CodeBuild | IAM Role 직접 사용 |
| AWS Lambda + EventBridge | SAM (CFN 확장) | Slide 23 패턴 |
| AWS Glue + RDS | Ansible (GHA + OIDC + SSM → CN) | GitOps · git state로 reconcile |
| Azure 인프라+콘텐츠 | Bicep + GitHub Actions OIDC | workflow JSON 인라인 |
| GCP 인프라+콘텐츠 | Terraform + GitHub Actions WIF | `archive_file`로 CF 코드 인라인 |

## 비용 구조 (~$203/월 · 도쿄 · 25 영업일)

| 구분 | 월 비용 |
|---|---|
| 🔒 영구 (24/7 유지) | ~$16 |
| ⏰ 매일 destroy/create (9-18) | ~$111 |
| 📆 Phase 기반 (TGW · VPN · Client VPN · WAF · Glue) | ~$77 |
| **합계** | **~$203** |
| 24/7 환산 시 | ~$900 (-78%) |

## Day-to-Day 운영

```bash
# 09:00 아침
./scripts/start-day.sh   # 00 + 10 + 20 + 30 + 40 + CI/CD 전부 deploy

# 작업 중
git push origin main     # → CodePipeline / GHA 자동 트리거

# 18:00 저녁
./scripts/stop-day.sh    # 모든 daily 자원 destroy (역순)
```

## 팀 구성

- **김영헌 (영헌)** — 초기 시드 데이터 + MSA 전체 + AWS IaC
- **서민지 (민지)** — 판매 ETL (POS → Glue → S3 Mart) + 출판사 채널 + Azure IaC + Logic Apps
- **황우혁 (우혁)** — GCS staging → GCP 워크플로우 → Vertex AI 학습 + GCP IaC + PPT 추합

## 프로젝트 정보

- **발표일**: 2026-06-02
- **리전**: Asia Pacific (Tokyo) ap-northeast-1
- **운영 패턴**: 매일 9-18 (9h) × 25 영업일 · 주말·야간 destroy
