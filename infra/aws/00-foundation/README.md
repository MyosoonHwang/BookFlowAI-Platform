# Tier 00 · Foundation (🔒 영구 자원)

## 이 Tier의 역할

BOOKFLOW 프로젝트 전체의 **근간이 되는 영구 자원**들. 한번 배포하면 발표일까지 유지.

- 신뢰 체인 (IAM OIDC · KMS · ACM)
- 비밀 보관 (Secrets Manager)
- 데이터·이미지·코드 보존 (S3 · ECR)
- 감사·관측 (CloudTrail · CloudWatch Log Groups)
- 공통 설정값 (Parameter Store)
- 외부 연결 (CodeStar Connection)

**라이프사이클**: 🔒 영구 · Day 0에 `phase0-foundation.ps1` 1회 실행하면 끝.

## 이 폴더에 들어가는 Stack (10개)

| # | YAML | 자원 | 스코프 |
|---|---|---|---|
| 1 | `iam.yaml` | OIDC Provider + GHA Role 2 | GitHub Actions가 AWS 호출할 때 쓰는 federated auth. GHA는 Glue/RDS Ansible trigger (SSM SendCommand)만. CFN deploy는 로컬에서 수행 |
| 2 | `kms.yaml` | CMK × 2 (EKS envelope · CloudTrail) | 암호화 키. EKS Secret 암호화 + CloudTrail 로그 암호화. Key Rotation 활성 |
| 3 | `parameter-store.yaml` | SSM Parameter Store 13개 | 공통 설정값 (region · VPC CIDR · TGW ASN · Azure/GCP IP placeholder 등). Standard tier 무료 |
| 4 | `secrets.yaml` | Secrets Manager 6개 | Entra Client Secret · RDS password · Aladin TTB · 공공데이터 · GCP SA · SNS gen config. **값은 Phase 2에서 Ansible/secret-forwarder가 주입** |
| 5 | `acm.yaml` | ACM cert skeleton | Client VPN 서버 인증서 ARN을 Parameter Store에 기록. 실제 cert는 `easy-rsa` 생성 후 `aws acm import-certificate` 수동 import |
| 6 | `ecr.yaml` | ECR Repo × 12 | Pod 8 (auth · dashboard-bff · forecast · decision · intervention · inventory · notification · publisher-watcher) + ECS 3 (online-sim · offline-sim · inventory-api) + Publisher 1 |
| 7 | `codestar-connection.yaml` | GitHub Connection | CodePipeline이 bookflow-apps 레포 참조할 때 사용. **⚠ 배포 후 Console 수동 Activate 필요** (PENDING → AVAILABLE) |
| 8 | `s3.yaml` | S3 Bucket × 6 | `raw` (POS+SNS+알라딘+공공데이터 저장) · `mart` (Glue ETL 결과) · `audit` (CloudTrail 로그 · Object Lock 90d) · `tf-state` · `cp-artifacts` · `glue-scripts` |
| 9 | `cloudtrail.yaml` | CloudTrail Trail | Management events 전체 기록 → audit bucket 저장 · KMS 암호화 · 감사 의무 영구 |
| 10 | `cloudwatch.yaml` | Log Groups × 9 | EKS Cluster + Container Insights 2개 + Lambda 6개. retention 7일. ※ AWS SNS Topic 없음 (알림은 Azure Logic Apps로 통일) |

## 배포 순서 (의존성 기반)

```
1. iam                   ← 독립
2. kms                   ← 독립
3. parameter-store       ← 독립
4. secrets               ← 독립
5. acm                   ← 독립
6. ecr                   ← 독립
7. codestar-connection   ← 독립
8. s3                    ← kms Import (audit bucket 암호화)
9. cloudtrail            ← s3 + kms Import
10. cloudwatch           ← 독립
```

의존성이 있는 것만 순서 중요: **kms → s3 → cloudtrail** 체인. 나머지는 순서 무관.

## 배포 방법

```powershell
cd BookFlowAI-Platform
.\scripts\aws\0-initial\phase0-foundation.ps1
```

단일 Stack만 올리거나 update하려면:
```powershell
. .\scripts\aws\_lib\deploy-stack.ps1
Deploy-Stack -Tier "00" -Name "iam" -Template "00-foundation/iam.yaml"
```

## 배포 후 수동 작업

### 1. ACM Client VPN Cert Import
```bash
# easy-rsa로 cert 생성 (Linux/WSL 환경)
git clone https://github.com/OpenVPN/easy-rsa.git
cd easy-rsa/easyrsa3
./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa build-server-full server nopass
./easyrsa build-client-full client1.domain.tld nopass

# AWS ACM 에 import
aws acm import-certificate \
  --certificate fileb://pki/issued/server.crt \
  --private-key fileb://pki/private/server.key \
  --certificate-chain fileb://pki/ca.crt \
  --region ap-northeast-1
# → 받은 ARN을 acm.yaml 파라미터로 재-deploy
```

### 2. CodeStar Connection Activate
AWS Console → Developer Tools → Settings → Connections →
PENDING 상태 connection 클릭 → **Update pending connection** → GitHub App 설치 권한 승인 → AVAILABLE 확인

## 제공되는 Export (다른 Tier가 Import)

| Export Name | 쓰는 곳 |
|---|---|
| `bookflow-iam-oidc-provider-arn` | GHA workflow |
| `bookflow-iam-gha-glue-redeploy-role-arn` | `.github/workflows/glue-redeploy.yml` |
| `bookflow-iam-gha-rds-redeploy-role-arn` | `.github/workflows/rds-redeploy.yml` |
| `bookflow-kms-eks-arn` | 30-compute-cluster/eks-cluster |
| `bookflow-kms-cloudtrail-arn` | s3 (audit encryption) · cloudtrail |
| `bookflow-s3-raw-name` / `-mart-name` / `-audit-name` 등 | 10-kinesis(firehose) · 99-glue · 99-serverless |
| `bookflow-ecr-registry-uri` · `-repo-prefix` | 40-compute-runtime · CodePipeline |
| `bookflow-codestar-github-connection-arn` | cicd/codepipeline/* |
| `bookflow-secrets-entra-client-arn` 등 | SAM · Pod · Logic Apps |
| `bookflow-cw-eks-log-group` | 30-eks-cluster |

## 제외된 것 (다른 Tier에)

- **Route 53 Private Hosted Zone** → 20a-network-core에서 (VPC 필요)
- **Pod별 IRSA Role** → 30-compute-cluster + 40-compute-runtime 각각
- **RDS Enhanced Monitoring Role** → 10-data-persistent/rds.yaml
- **Lambda Execution Role** → SAM이 자동 생성 (99-serverless)
- **CodePipeline/CodeBuild Service Role** → cicd/codepipeline/*.yaml 각각
- **Ansible CN EC2 Role + Profile** → 30-compute-cluster/control-node.yaml
- **Athena WorkGroup** (필요 시 99-glue에 추가)

## 검증

```powershell
# 각 yaml cfn-lint
cfn-lint infra\aws\00-foundation\*.yaml

# stack 현황 확인
. .\scripts\aws\_lib\check-stack.ps1
Show-AllStacks
```

## 수정 시

- 기존 자원 update는 CFN이 idempotent하게 처리 (노-diff면 skip)
- 공통 Parameter(`ProjectName` 등) 바꾸면 Export 이름도 바뀜 → 다른 Tier 모두 재배포 필요
- Secret value는 이 stack에서 변경하지 말 것 (skeleton 유지) · Phase 2 Ansible이 주입
