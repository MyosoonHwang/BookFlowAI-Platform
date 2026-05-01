# BookFlowAI Platform - Team Quick Read

이 문서는 팀원이 repo를 처음 내려받았을 때 전체 구조와 작업 규칙을 빠르게 이해하기 위한 안내입니다.

참고 기준 문서:

- `D:\gcp\AGENTS.md`
- `D:\gcp\ARCHITECTURE.md`
- `SETUP.md`

## 1. 핵심 구조

BookFlowAI는 AWS, Azure, GCP를 함께 쓰는 multi-cloud 프로젝트입니다.

```text
                    AWS
          Main Hub / App / Data / CI/CD
              Transit Gateway
              /              \
             /                \
      Site-to-Site VPN   Site-to-Site VPN
           /                  \
        Azure                GCP
   Auth / Notify        AI / Analytics
```

역할 분담:

| Cloud | 역할 | 주요 서비스 |
|---|---|---|
| AWS | 허브, 애플리케이션, 데이터, CI/CD | TGW, EKS, ECS, RDS, Lambda, Kinesis, Glue, Step Functions |
| Azure | 인증, 알림, secret 관리 | Entra ID, Key Vault, Logic Apps, Event Grid, Function |
| GCP | AI 예측, 분석, 데이터 웨어하우스 | Vertex AI, BigQuery, GCS, Cloud Functions, Workflows |

가장 중요한 원칙은 **AWS가 hub/source of truth**라는 점입니다. Azure와 GCP는 서로 직접 연결하지 않고, 각각 AWS Transit Gateway에 Site-to-Site VPN으로 연결됩니다.

## 2. 절대 수정 금지 영역

현재 GCP 작업자는 다음 파일 영역을 **절대 수정하지 않습니다.**

```text
infra/aws
infra/azure
scripts/azure
```

이 영역은 읽기 전용입니다. AWS/Azure 값이 필요하면 기준값 확인용으로만 읽고, 변경은 GCP 쪽 파일이나 공통 문서에만 합니다.

GCP 작업 중 수정 가능한 대표 영역:

```text
infra/gcp
scripts/gcp
READ.md
SETUP.md
```

## 3. 처음 설치

Windows PowerShell에서 repo root로 이동한 뒤 실행합니다.

```powershell
.\scripts\setup-dev.ps1
.\.venv\Scripts\Activate.ps1
```

규칙:

- Python 가상환경은 repo root의 `.venv` 하나만 사용합니다.
- `venv`, `scripts\.venv` 같은 별도 환경은 만들지 않습니다.
- Python 의존성은 `scripts\requirements.txt`를 기준으로 설치합니다.

환경을 다시 만들 때:

```powershell
.\scripts\setup-dev.ps1 -Recreate
```

기존 테스트용 가상환경을 정리할 때:

```powershell
.\scripts\setup-dev.ps1 -RemoveOldVenvs
```

## 4. 담당 영역

| 담당 | 작업 위치 |
|---|---|
| AWS | `infra/aws` |
| Azure | `infra/azure`, `scripts/azure` |
| GCP | `infra/gcp`, `scripts/gcp` |

GCP 작업자는 AWS/Azure 파일을 수정하지 않고, 필요한 값만 확인합니다.

## 5. AWS Hub와 GCP 연결

GCP 네트워크는 다음 경로로 AWS에 연결됩니다.

```text
GCP VPC
  -> Cloud Router
  -> HA VPN
  -> AWS Site-to-Site VPN
  -> AWS Transit Gateway
  -> AWS VPCs
```

GCP daily network layer:

```text
infra/gcp/20-network-daily/
  data.tf
  cloud-router.tf
  vpn.tf
  psc.tf
  variables.tf
  terraform.tfvars
```

AWS 기준값 확인용 파일:

```text
infra/aws/10-network-core/customer-gateway.yaml
infra/aws/60-network-cross-cloud/tgw.yaml
infra/aws/60-network-cross-cloud/vpn-site-to-site.yaml
infra/aws/60-network-cross-cloud/tgw-vpc-routes.yaml
```

주의: 위 AWS 파일들은 **읽기 전용**입니다.

## 6. AWS Credential 없이 GCP 작업하는 방식

현재 GCP Terraform은 AWS API에 직접 접속해서 값을 가져오지 않습니다. 즉, GCP 작업자가 AWS credential을 설정하지 않아도 됩니다.

방식:

```text
AWS 파일을 기준값으로 확인
-> GCP terraform.tfvars에 변수값으로 반영
-> GCP Terraform은 var.xxx로 사용
```

예:

```hcl
aws_tgw_bgp_asn = 64512
aws_vpc_cidrs   = ["10.0.0.0/16", "10.1.0.0/16", "10.2.0.0/16", "10.3.0.0/16"]

aws_peer_ips = [
  "AWS_TUNNEL_0_OUTSIDE_IP",
  "AWS_TUNNEL_1_OUTSIDE_IP"
]

gcp_routed_cidr          = "192.168.10.0/24"
psc_endpoint_host_offset = 10
```

## 7. Hard-coding 금지

Terraform 리소스 코드에는 환경별 값을 직접 넣지 않습니다.

금지:

```hcl
name     = "bookflow-vpc"
address  = "192.168.10.10"
peer_asn = 64512
```

권장:

```hcl
name     = var.vpc_name
address  = cidrhost(var.gcp_routed_cidr, var.psc_endpoint_host_offset)
peer_asn = var.aws_tgw_bgp_asn
```

값은 다음 방식으로 전달합니다.

- `var.xxx`
- `local.xxx`
- `data.xxx`
- `terraform.tfvars`
- cloud output 또는 parameter 값

## 8. GCP 비용 절감 운영

계속 유지하는 foundation layer:

```text
infra/gcp/00-foundation
```

작업 시간에만 사용하는 daily/content layer:

```text
infra/gcp/20-network-daily
infra/gcp/99-content
```

시작:

```powershell
.\scripts\gcp\start-day.ps1
```

종료:

```powershell
.\scripts\gcp\stop-day.ps1
```

종료 순서:

```text
1. 99-content destroy
2. 20-network-daily destroy
3. 00-foundation 유지
```

이 순서를 지켜야 Vertex AI, Cloud Functions, VPN/PSC 같은 비용 리소스를 먼저 제거하고, VPC/GCS/BigQuery 같은 foundation은 다음 작업일에 재사용할 수 있습니다.

## 9. GCP 데이터 흐름

현재 GCP content 흐름:

```text
GCS staging upload
  -> Eventarc
  -> Cloud Workflows
  -> bq-load Cloud Function
  -> BigQuery
  -> dry-run mode: Vertex AI Pipeline skip
```

기존 도서 예측:

```text
GCS staging file
  -> BigQuery load
  -> feature engineering
  -> Vertex AI Pipeline
  -> model registry / endpoint / batch prediction
  -> forecast_results
```

신간 예측:

```text
publish-watcher
  -> notification-svc
  -> manager starts forecast
  -> forecast-svc
  -> GCP Cloud Function feature assembly
  -> existing Vertex AI Endpoint real-time inference
```

중요: **신간 예측은 Vertex AI Pipeline을 새로 돌리지 않습니다.** 기존 학습/배포된 모델 endpoint를 재사용합니다.

## 10. 중요 아키텍처 제약

반드시 지킬 것:

- 모든 inventory write는 `inventory-svc`만 수행합니다.
- 신간 예측은 Vertex AI Pipeline을 사용하지 않습니다.
- GCP 연결은 VPN 또는 Private Service Connect만 사용합니다.
- Lambda 배포는 SAM Canary 전략을 사용합니다.
- EKS Secret은 External Secrets Operator로 관리합니다.
- Glue와 RDS 배포는 Ansible Control Node를 통해 수행합니다.
- Publisher API는 API Key와 Rate Limiting 전까지 production 노출 금지입니다.

## 11. 서비스 흐름 요약

운영 서비스 흐름:

```text
User / Publisher
  -> Route 53 / WAF / ALB
  -> AWS EKS services
  -> RDS / Redis
  -> Azure Logic Apps for notification
  -> GCP BigQuery / Vertex AI for forecasting
```

주요 EKS 서비스:

| Service | 역할 |
|---|---|
| `auth-pod` | Azure Entra ID OIDC 인증 |
| `dashboard-svc` | frontend/backend gateway, WebSocket hub |
| `forecast-svc` | GCP BigQuery / Vertex AI 진입점 |
| `decision-svc` | 재배치, 지역 재분배, EOQ 주문 판단 |
| `intervention-svc` | 승인/실행 gateway |
| `inventory-svc` | 유일한 inventory write entry point |
| `notification-svc` | Azure Logic Apps, Teams, Outlook 연결 |
| `publish-watcher` | 신간 요청 감지 CronJob |

## 12. 검증 명령

작업 전:

```powershell
git status
```

GCP Terraform 검증:

```powershell
terraform -chdir="infra/gcp/00-foundation" validate
terraform -chdir="infra/gcp/20-network-daily" validate
terraform -chdir="infra/gcp/99-content" validate
```

GCP와 AWS 기준값을 맞출 때 확인할 것:

- AWS TGW ASN과 GCP `aws_tgw_bgp_asn` 일치
- AWS VPN tunnel CIDR과 GCP `bgp_sessions` 일치
- AWS route의 `GcpVpcCidr`와 GCP `gcp_routed_cidr` 일치
- PSC endpoint가 `gcp_routed_cidr` 안에서 계산되는지 확인
- AWS/Azure 파일 수정 없음

## 13. Commit 전 체크

```powershell
git status --short
```

확인할 것:

- `infra/aws` 변경 없음
- `infra/azure` 변경 없음
- `scripts/azure` 변경 없음
- secret, credential, key 파일 없음
- `.venv`, `venv`, `.terraform`, `*.tfstate` 같은 로컬 산출물 없음

## 14. 기억할 한 줄

```text
AWS is the hub. Azure and GCP connect to AWS. GCP work must not modify AWS or Azure files.
```
