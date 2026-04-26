# AWS 배포 스크립트 (영헌 담당)

> BOOKFLOW AWS 인프라 배포 스크립트 모음. **Windows PowerShell (.ps1)** 환경.
> 모든 스크립트는 `scripts/aws/_lib/common.ps1` 을 dot-source 해서 공용 함수 사용.

## 디렉토리 구조

```
scripts/aws/
├── config/            공유 설정 (aws.ps1 · aws.local.ps1.example)
├── _lib/              공용 함수 (common · deploy-stack · destroy-stack · check-stack)
├── 0-initial/         최초 1회 · 멀티클라우드 통신 검증
├── 1-daily/           매일 아침/저녁 (base-up · base-down)
├── 2-tasks/           작업 단위별 add-on (base 위에 쌓기)
└── utils/             유틸 (cross-cloud exports 등)
```

## 최초 setup (영헌 1회만)

```powershell
# PowerShell Execution Policy 허용
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# AWS CLI 설치 확인
aws --version

# AWS 자격 증명 설정 (CFN deploy 로컬 수행용)
aws configure
# AWS Access Key ID: ...
# AWS Secret Access Key: ...
# Default region name: ap-northeast-1
# Default output format: json

# 개인 config 생성 (필요 시)
Copy-Item config\aws.local.ps1.example config\aws.local.ps1
# 수정: aws.local.ps1
```

### IAM 역할 구분

| 주체 | 권한 | 용도 |
|---|---|---|
| **로컬 `aws configure` IAM User** (영헌) | CFN deploy 권한 필요 | 모든 `aws cloudformation deploy` 실행 주체 |
| **GhaGlueRedeployRole** (GHA OIDC) | `ssm:SendCommand` 만 | `.github/workflows/glue-redeploy.yml` 에서 assume |
| **GhaRdsRedeployRole** (GHA OIDC) | `ssm:SendCommand` 만 | `.github/workflows/rds-redeploy.yml` 에서 assume |

→ GHA는 SSM으로 Ansible CN만 트리거. 실제 인프라 변경은 Ansible CN이 수행.
→ CFN deploy는 로컬 (영헌 PowerShell)에서만 수행. GHA에 CFN 권한 Role 없음.

## 일상 사용법

### 매일 아침 09:00
```powershell
cd BookFlowAI-Platform
.\scripts\aws\1-daily\base-up.ps1
# → 자동으로 show-cross-cloud-exports.ps1 실행
# → exports/aws-YYYY-MM-DD.txt 생성
# → 팀 단톡에 복붙
```

### 작업 단위별 add-on
```powershell
# MSA Pod 개발
.\scripts\aws\2-tasks\task-msa-pods.ps1

# auth-pod 개발 (+ Azure VPN)
.\scripts\aws\2-tasks\task-auth-pod.ps1

# ETL1 POS (민지)
.\scripts\aws\2-tasks\task-etl-streaming.ps1
```

### 매일 저녁 18:00
```powershell
.\scripts\aws\1-daily\base-down.ps1
# → 전체 역순 destroy (base + 모든 task 포함)
```

## Stack 배포 순서 (의존성 기반)

CloudFormation Stack은 **Outputs + Import** 관계 때문에 순서가 중요함. 스크립트가 자동 처리.

### Tier 00 Foundation (Day 0 1회 · phase0-foundation.ps1) · 10 stack

```
 1. iam                   ← GHA OIDC + GHA Role 2개 (SSM 트리거 전용)
 2. kms                   ← CMK × 2 (EKS envelope + CloudTrail)
 3. parameter-store       ← 공통 설정값 (독립)
 4. secrets               ← Secrets Manager skeleton (값 주입은 Phase 2)
 5. acm                   ← Client VPN cert (skeleton · easy-rsa import 필요)
 6. ecr                   ← 12 repo (Pod 8 + ECS 3 + Publisher 1)
 7. codestar-connection   ← GitHub OAuth (⚠ Console 수동 Activate 필요)
 8. s3                    ← 6 bucket (kms Import)
 9. cloudtrail            ← Trail (s3 + kms Import)
10. cloudwatch            ← Log Groups (EKS + Lambda 6종 + Alarm SNS)
```
※ `route53` (Private Hosted Zone)은 VPC 필요 → **20a-network-core에서 생성**
※ `codestar-connection` 은 deploy 후 AWS Console에서 GitHub App install 수동 승인 필요 (PENDING → AVAILABLE)

### Tier 10 Network Core (base-up · 모두 무료)

```
11. vpc-bookflow-ai        ← 독립
12. vpc-sales-data         ← 독립
13. vpc-egress             ← 독립 (+ IGW)
14. vpc-data               ← 독립 (Private + DB subnet)
15. vpc-ansible            ← Public + Private 혼합 (Ansible Node 인터넷 outbound)
16. customer-gateway       ← 독립 (IP placeholder OK)
17. route53                ← 5 VPC Import (Private Hosted Zone)
```
※ Endpoints (`endpoints-bookflow-ai`, `endpoints-sales-data`, `endpoints-ansible`) · Peering 은 base-up 제외 → 각 task 가 필요 시 deploy

### Tier 20 Data Persistent (task-data.ps1)

```
18. rds                    ← vpc-data DB subnet + 00-secrets + 00-kms Import
19. redis                  ← vpc-data DB subnet Import
20. kinesis                ← 00-s3 + 00-kms Import · VPC 독립
```

### Tier 30 Compute Cluster (분산 배포)

```
21. ecs-cluster              ← base-up · 무료
22. ansible-node             ← base-up · vpc-ansible Public subnet · ~$1/월
23. eks-cluster              ← task-msa-pods · 00-kms + vpc-bookflow-ai Import
24. eks-alb-controller-irsa  ← task-msa-pods · eks-cluster OIDC Import
25. eks-eso-irsa             ← task-msa-pods · ESO Pod 가 Secrets Manager 접근
```

### Tier 40 Compute Runtime (task-msa-pods · task-etl-streaming · task-publisher)

```
25. eks-nodegroup          ← task-msa-pods · eks-cluster Import (EC2 Managed Node Group)
26. eks-addons             ← task-msa-pods · vpc-cni · kube-proxy · coredns · ebs-csi · pod-identity
27. ecs-online-sim         ← task-etl-streaming · ecs-cluster + kinesis Import
28. ecs-offline-sim        ← task-etl-streaming · ecs-cluster + kinesis Import
29. ecs-inventory-api      ← task-publisher · ecs-cluster + rds Import (LB parameter)
30. publisher-asg          ← task-publisher · vpc-egress + 00-s3 Import (TG parameter)
```

### Tier 50 Network Traffic (task-publisher · task-auth-pod)

```
31. nat-gateway            ← task-auth-pod · NAT × 2 (Multi-AZ HA · TGW 활성 시 cross-VPC)
32. alb-external           ← task-publisher · ALB + Listener 80/8080 + 3 Target Groups
33. waf                    ← task-publisher · WAFv2 + Managed Rules + Rate Limit
```

### Tier 60 Network Cross-Cloud (task-auth-pod · task-forecast · task-client-vpn)

```
34. tgw                    ← TGW Hub + 4 VPC Attachment (Ansible 제외) + RT
35. vpn-site-to-site       ← Azure / GCP S2S VPN · CGW IP parameter (env var)
36. client-vpn             ← Endpoint + Subnet Assoc + Auth Rule + ACM cert
```

### Tier 99 Serverless / Glue (task-lambdas · task-glue)

```
37. 99-lambdas (SAM)       ← 7 Lambdas + EventBridge cron 5 + Kinesis ESM + API Gateway HTTP
                              CAPABILITY_AUTO_EXPAND 필수
38. 99-glue-catalog        ← Glue Database + 6 Jobs (Flex DPU) + IAM + BigQuery Connection
39. 99-step-functions      ← ETL3 State Machine (Glue 6 Jobs orchestration · forecast-trigger Lambda 가 invoke)
```

---

## 스크립트 매트릭스

| 스크립트 | 언제 | 올리는 것 | 비용/일 |
|---|---|---|---|
| `0-initial/full-cross-cloud-test.ps1` | 최초 1회 / Phase 3 통합 | base + 전체 task + Azure·GCP VPN + TGW | ~$8 |
| `1-daily/base-up.ps1` | 매일 09:00 | Tier 10 VPC + ECS Cluster + ALB IRSA + Ansible Node | **~$1** (최소) |
| `1-daily/base-down.ps1` | 매일 18:00 | 전체 역순 destroy | $0 |
| `2-tasks/task-data.ps1` | DB 작업 시 (전제) | RDS + Redis + Kinesis | +$1.30 |
| `2-tasks/task-msa-pods.ps1` | EKS Pod 개발 | EKS Cluster + Node Group + Addons + endpoints-bookflow-ai | +$1.20 |
| `2-tasks/task-etl-streaming.ps1` | ETL1 POS 시뮬 | ECS sims + endpoints-sales-data | +$0.40 |
| `2-tasks/task-publisher.ps1` | 출판사 채널 | Publisher ASG + ECS inventory-api + Tier 50 (ALB · WAF) | +$1.20 |
| `2-tasks/task-auth-pod.ps1` | Auth Pod 작업 | NAT + Azure VPN + Secrets endpoints | +$1.50 |
| `2-tasks/task-forecast.ps1` | Vertex AI 통신 | GCP HA VPN | +$1.50 |
| `2-tasks/task-rds-seed.ps1` | DB 시드 주입 | (자원 없음 · Ansible playbook 트리거) | $0 |
| `2-tasks/task-lambdas.ps1` | ETL · forecast · auth Lambda | 7 Lambdas + EventBridge + Kinesis ESM + API Gateway | ~$0 (free tier) |
| `2-tasks/task-glue.ps1` | ETL3 Raw → Mart 정제 | Glue DB + 6 Jobs + Step Functions ETL3 + (lambdas 자동 SF ARN 주입) | ~$4 |
| `2-tasks/task-client-vpn.ps1` | 3 담당자 VPN access | Client VPN Endpoint + Subnet Assoc + Auth | +$1.50 |
| `2-tasks/task-full-stack.ps1` | **시연·통합 · wrapper** | data + msa-pods + etl-streaming + publisher 순차 실행 | ~$5.60 |
| `2-tasks/task-scenario-ha.ps1` | HA 시나리오 시연 | RDS Multi-AZ + Redis Replication 전환 | +$0.30 |
| `2-tasks/task-scenario-ha-revert.ps1` | HA 시나리오 후 복귀 | 구축 모드 (Single-AZ · SingleNode) 복귀 | $0 |
| `utils/show-cross-cloud-exports.ps1` | base-up 후 자동 | — (Azure/GCP 팀 공유 값 출력) | $0 |

## 작업 단위별 매핑 (V4 WBS)

| WBS | 작업 | 담당 | 스크립트 |
|---|---|---|---|
| 4 | RDS 시드 | 영헌 | `task-rds-seed` |
| 5 | Vertex 최초 학습 | 우혁 | `task-forecast` |
| 6 | ETL1 POS | 민지 | `task-etl-streaming` |
| 7 | ETL2 외부 | 민지 | `task-etl-batch` |
| 8 | ETL3 Raw→Mart | 민지 | `task-etl-batch` |
| 9 | DW 일상 AI | 우혁 | `task-forecast` |
| 10.1 | EKS 기초 | 영헌 | `task-msa-pods` |
| 10.2 | auth-pod | 영헌 | `task-auth-pod` |
| 10.3~8 | Pod 개발 | 영헌 | `task-msa-pods` |
| 10.9 | dashboard-bff | 영헌 | `task-msa-pods` (Internal ALB 자동) |
| Publisher | - | - | `task-publisher` |
| 11 | 통합 테스트 | 전원 | `0-initial/full-cross-cloud-test` |

## Cross-cloud Exports

매일 아침 `base-up.ps1` 실행 후 자동으로 `show-cross-cloud-exports.ps1`이 실행됨.

출력 내용:
- AWS Customer Gateway Public IP (Azure/GCP VPN 설정용)
- AWS Site-to-Site VPN Public IP × 2
- AWS TGW ID · BGP ASN
- 4 VPC CIDR blocks

출력물은 `exports/aws-YYYY-MM-DD.txt` 에 저장 (`.gitignore`로 GitHub 제외).
영헌이 팀 단톡/Slack에 복붙해서 민지(Azure) · 우혁(GCP)에게 공유.

## Config 설명

### `config/aws.ps1` (공유 · git)
공통 설정값. 팀 전체 동일.
```powershell
$env:AWS_REGION      = "ap-northeast-1"
$env:STACK_PREFIX    = "bookflow"
$env:ACCOUNT_ID      = "111122223333"
$env:GITHUB_REPO     = "MyosoonHwang/BookFlowAI-Platform"
```

### `config/aws.local.ps1` (개인 · gitignored)
개인별 override. 필요 시 `aws.local.ps1.example` 복사해서 사용.
```powershell
# 예: 다른 AWS profile 쓰고 싶을 때
$env:AWS_PROFILE = "bookflow-personal"
```

## 트러블슈팅

### Execution Policy 오류
```
.\scripts\aws\1-daily\base-up.ps1 cannot be loaded because running scripts is disabled
```
→ `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` 1회 실행

### AWS 자격 증명 오류
```
Unable to locate credentials
```
→ `aws configure` 실행 또는 `config/aws.local.ps1` 에서 `$env:AWS_PROFILE` 설정

### Stack이 이미 존재
CFN은 idempotent. 이미 있으면 `UPDATE_COMPLETE` 또는 `No updates are to be performed`. 정상.

### 의존성 순서 오류 (Import 실패)
순서대로 deploy해야 함. 예: `30-eks-cluster`가 `00-kms` Output 을 Import하려면 `00-kms`가 먼저 배포돼야 함.
→ `base-up.ps1` 사용하면 올바른 순서로 자동 deploy.

## 새 스크립트 추가 가이드

1. 적절한 디렉토리 선택:
   - 1회만 쓸 거면 `0-initial/`
   - 매일 쓸 거면 `1-daily/`
   - 특정 작업 시에만 쓸 거면 `2-tasks/`
   - 유틸리티면 `utils/`
2. 파일명 규칙: `task-XXX.ps1` · `base-XXX.ps1` 등 일관성 유지
3. 상단에 `. $PSScriptRoot\..\_lib\common.ps1` 로 common 로드
4. `deploy_stack` 함수 사용 (수동 `aws cloudformation deploy` 호출 지양)
5. README 이 파일에 매트릭스 업데이트
