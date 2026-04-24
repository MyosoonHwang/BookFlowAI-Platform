# Tier 10 · Network Core (⏰ 매일 destroy/create)

## 이 Tier의 역할

**5개 VPC · Peering · Interface Endpoints · Customer Gateway · Private DNS Zone** — 다른 모든 Tier의 네트워크 근간.

라이프사이클: ⏰ 매일 · `base-up.ps1` 이 아침에 올림 · `base-down.ps1` 이 저녁에 내림.

## VPC 구성 (5개)

| VPC | CIDR | Subnet | IGW | 용도 |
|---|---|---|---|---|
| **BookFlow AI** | `10.0.0.0/16` | Private × 2 AZ | — | EKS Pod · MSA 서비스 |
| **Sales Data** | `10.1.0.0/16` | Private × 2 AZ | — | POS 시뮬 ECS Fargate |
| **Egress** | `10.2.0.0/16` | **Public × 2 AZ** | ✅ | DMZ · NAT · 재고조회 ALB+ECS · Publisher EC2 |
| **Data** | `10.3.0.0/16` | Private + DB × 2 AZ | — | RDS PostgreSQL + ElastiCache Redis |
| **Ansible** | `10.4.0.0/16` | Private × 2 AZ | — | Ansible Control Node t3.nano |

## 이 폴더의 Stack (14개)

### 🏗 VPC 기본 (5 파일 · 독립 deploy 순서 무관)

| YAML | 내용 |
|---|---|
| `vpc-bookflow-ai.yaml` | BookFlow AI VPC + Subnet × 2 + Route Table |
| `vpc-sales-data.yaml` | Sales Data VPC |
| `vpc-egress.yaml` | Egress VPC + IGW + Default Route 0.0.0.0/0 → IGW |
| `vpc-data.yaml` | Data VPC + Private RT + DB RT |
| `vpc-ansible.yaml` | Ansible VPC |

### 🛡 Customer Gateway (1 파일)

| YAML | 내용 |
|---|---|
| `customer-gateway.yaml` | Azure CGW + GCP CGW (IP placeholder 0.0.0.0 · Phase 2 재배포로 실 IP 주입) |

Customer Gateway는 VPN peer IP 정의용. **Cross-cloud 트래픽 흐름**:
```
AWS VPC → Transit Gateway (60) → Site-to-Site VPN (60) → IPsec tunnel → Azure/GCP VPN Gateway
                                       ↑
                            Customer Gateway (10) ← peer IP 정의
```
Phase 3 시나리오 테스트 때 TGW + VPN 활성화 · 이때 CGW IP 필요.

### 🌐 Route 53 (1 파일 · 5 VPC 모두 필요)

| YAML | 내용 |
|---|---|
| `route53.yaml` | Private Hosted Zone `vpn.bookflow.internal` · 5 VPC 전부 association |

### 🔗 Interface Endpoints (per VPC · 3 파일)

Endpoint는 **대상 AWS 서비스 엔드포인트와 연결** (내 계정 리소스 무관). 필요한 VPC에만 배치.

| YAML | 배치 VPC | Endpoint 목록 |
|---|---|---|
| `endpoints/endpoints-bookflow-ai.yaml` | BookFlow AI | ECR api/dkr · Kinesis · SSM · Secrets · CW Logs · KMS + S3 Gateway (7 Interface + 1 Gateway) |
| `endpoints/endpoints-sales-data.yaml` | Sales Data | ECR api/dkr · Kinesis + S3 Gateway (3 + 1) |
| `endpoints/endpoints-ansible.yaml` | Ansible | SSM · SSMMessages · EC2Messages · Secrets · Glue + S3 Gateway (5 + 1) |

※ 모든 Interface Endpoint는 **단일 AZ (AZ1)**에만 배치 (학프 비용 최적화).

### 🔁 VPC Peering (per pair · 5 파일)

**구축·개발 기간 전용** (Phase 1-2). 최초 TGW 동작 검증 후 Phase 3부터 TGW로 전환.

| YAML | 연결 |
|---|---|
| `peering/bookflow-ai-data.yaml` | EKS Pod ↔ RDS/Redis |
| `peering/bookflow-ai-egress.yaml` | auth-pod ↔ NAT · Pod ↔ ALB |
| `peering/sales-data-egress.yaml` | POS 시뮬 ↔ 재고조회 API |
| `peering/egress-data.yaml` | 재고조회 ECS ↔ RDS |
| `peering/ansible-data.yaml` | Ansible CN ↔ RDS (스키마 관리 · seed 주입) |

## 배포 순서 (base-up.ps1)

```
1. vpc-bookflow-ai, vpc-sales-data, vpc-egress, vpc-data, vpc-ansible  ← 병렬 가능 · 모두 독립
2. customer-gateway                                                     ← 독립 (IP 있을 때만 실제 리소스 생성)
3. route53                                                              ← 5 VPC Import 필요 → 1 뒤에
```

**Endpoints · Peering은 base-up에 포함 안 함** → **task 스크립트가 필요 시** deploy (`2-tasks/task-*.ps1`).

## 다른 Tier와의 관계

- Tier 20 (data-persistent): `vpc-data` Subnet Import → RDS/Redis Subnet Group
- Tier 30 (compute-cluster): `vpc-bookflow-ai` Subnet Import → EKS · ECS Cluster
- Tier 40 (compute-runtime): Subnet Import → Node/Service 배치
- Tier 50 (network-traffic): `vpc-egress` Import → NAT GW · ALB
- Tier 60 (network-cross-cloud): CGW Import → VPN · TGW VPC Attach

## 검증

```powershell
# lint
cfn-lint infra\aws\10-network-core\**\*.yaml

# deploy 후 stack 상태 확인
. .\scripts\aws\_lib\check-stack.ps1
Show-AllStacks

# VPC CIDR 확인
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=bookflow-vpc-*" --query 'Vpcs[].[Tags[?Key==`Name`]|[0].Value,CidrBlock]' --output table
```

## 수동 후속 작업

### Customer Gateway IP 주입 (Phase 2)

Azure/GCP 팀이 자기 VPN Gateway Public IP 확정 후:
```powershell
Deploy-Stack -Tier "10" -Name "customer-gateway" -Template "10-network-core/customer-gateway.yaml" `
  -Parameters @{ AzureVpnGatewayIp = "203.0.113.10"; GcpHaVpnIp = "203.0.113.20" }
```

## 비용 추정 (Tier 10)

| 자원 | 시간당 | 월 비용 (198h × 22d) |
|---|---|---|
| VPC × 5 | 0 | **$0** (무료) |
| IGW × 1 | 0 | $0 |
| Peering × 4 | 0 | $0 (데이터만 과금) |
| Route 53 Private Zone × 1 | — | $0.50/월 (fixed) |
| Interface Endpoint × 15 | $0.014 × 15 | $41.58 (15 ENI × 198h) — 단 task가 필요한 것만 배포하면 훨씬 적음 |
| S3 Gateway Endpoint × 3 | 0 | $0 |
| Customer Gateway × 2 | 0 | $0 |

※ Endpoints는 task 스크립트가 필요 시 배포 → 실제로는 BookFlow AI (7) + Sales Data (3) + Ansible (5) × 가동 시간 누적.
