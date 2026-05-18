# Cross-Cloud VPN 연결 가이드 (AWS ↔ GCP)

BookFlow 발표일 전용. AWS Transit Gateway 기반 Site-to-Site VPN으로 GCP를 연결한다.

---

## 구성 개요

```
GCP HA VPN (interface 0)
  34.157.64.22
       │  IKEv2 / BGP ASN 64514
       │
  ─────┴──────────────────────────────────
          AWS Transit Gateway (ASN 64512)
          ap-northeast-1
  ─────┬──────────────────────────────────
       │
  bookflow-ai VPC   sales-data VPC   data VPC   egress VPC ...
```

**터널 파라미터 (GCP)**

| | Tunnel 0 | Tunnel 1 |
|---|---|---|
| AWS 외부 IP | 동적 할당 | 동적 할당 |
| Inside CIDR | 169.254.213.136/30 | 169.254.100.72/30 |
| AWS BGP IP | 169.254.213.137 | 169.254.100.73 |
| GCP BGP IP | 169.254.213.138 | 169.254.100.74 |
| IKE | v2 / AES128 / SHA2-256 / DH14 | 동일 |
| GCP interface | 0 (양쪽 동일) | 0 (양쪽 동일) |
| 기본 운용 | **UP** | DOWN (비용 절감) |
| 최종 테스트 | UP | UP (`--full`) |

---

## 사전 준비 (1회)

### 1. GCP HA VPN Interface 0 IP 확인

```bash
gcloud compute vpn-gateways describe bookflow-aws-ha-vpn \
  --region=asia-northeast1 \
  --format="value(vpnInterfaces[0].ipAddress)"
# 고정값: 34.157.64.22
```

> **주의**: Interface 0 IP만 사용. Interface 1 IP를 입력하면 IKE 인증 실패.

### 2. `.env.local` 설정

```bash
# scripts/aws/config/.env.local
BOOKFLOW_GCP_VPN_GW_IP=34.157.64.22
GCP_PROJECT_ID=project-8ab6bf05-54d2-4f5d-b8d
```

### 3. gcloud 로그인 확인

```bash
gcloud config get account   # ms8405493@gmail.com 이어야 함
gcloud auth print-access-token | head -c 10   # ya29... 응답 확인
```

---

## 실행 (발표일 당일) — 스크립트 2개만 실행

### Step 1. AWS TGW + VPN 배포

```bash
cd BookFlowAI-Platform
bash scripts/aws/ops/network-mode.sh tgw
```

내부 순서:
1. `customer-gateway` 스택 — CGW 생성 (GCP interface 0 IP)
2. `tgw` 스택 — Transit Gateway 생성
3. `tgw-vpc-routes` + `vpn-site-to-site` 병렬 — VPC 라우트 + VPN 연결 (IKEv2)
4. TGW attachment → route table 연결 + BGP propagation 활성화

### Step 2. GCP 측 VPN 자동 구축

```bash
# 터널 1개 (기본 — 비용 절감)
bash scripts/aws/ops/gcp-vpn-info.sh

# 터널 2개 (최종 테스트용)
bash scripts/aws/ops/gcp-vpn-info.sh --full
```

이 스크립트가 자동으로 처리하는 작업:
1. AWS VPN 연결에서 터널 Outside IP / Inside CIDR / PSK 파싱
2. `infra/gcp/20-network-daily/terraform.tfvars` 생성
3. `terraform init` (최초 1회)
4. 기존 GCP 리소스 idempotent import (state 비어있어도 안전)
5. `terraform apply -auto-approve`
6. GCP 터널 상태 출력

---

## 상태 확인

### GCP 터널 상태

```bash
gcloud compute vpn-tunnels list \
  --project=project-8ab6bf05-54d2-4f5d-b8d \
  --format="table(name,status,detailedStatus)"
```

정상: `STATUS = ESTABLISHED`

### AWS 터널 상태

```bash
aws ec2 describe-vpn-connections \
  --filters "Name=tag:Name,Values=bookflow-vpn-gcp" \
  --query "VpnConnections[0].VgwTelemetry[*].{IP:OutsideIpAddress,Status:Status,Detail:StatusMessage}" \
  --output table --profile bookflow-deploy --region ap-northeast-1
```

정상: `Status = UP`, `Detail = X BGP ROUTES`

### TGW 라우트 테이블

```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <TGW_RT_ID> \
  --filters "Name=state,Values=active" \
  --query "Routes[*].{Dest:DestinationCidrBlock,Type:Type}" \
  --output table
```

정상 시 확인 경로:

| 목적지 | 출처 |
|--------|------|
| 10.0.0.0/16 ~ 10.4.0.0/16 | AWS VPC (propagated) |
| 10.50.0.0/24 | GCP PSC endpoint (BGP propagated) |

---

## 종료 (발표 후)

```bash
bash scripts/aws/ops/network-mode.sh peering
```

TGW + VPN 전체 삭제. GCP 측은 `terraform destroy` (`infra/gcp/20-network-daily/`).

---

## 트러블슈팅

### IPSEC IS DOWN (터널 미연결)

**원인 1: GCP IP 오입력** — Interface 0 IP가 아닌 Interface 1 IP를 입력한 경우

```bash
# GCP 실제 interface IP 확인
gcloud compute vpn-gateways describe bookflow-aws-ha-vpn \
  --region=asia-northeast1 \
  --format="table(vpnInterfaces[].id,vpnInterfaces[].ipAddress)"
```

불일치 시 → `network-mode.sh peering` 후 올바른 IP로 재실행.

**원인 2: PSK 불일치**

```bash
# AWS PSK 확인
aws ec2 describe-vpn-connections \
  --filters "Name=tag:Name,Values=bookflow-vpn-gcp" \
  --query "VpnConnections[0].Options.TunnelOptions[*].{IP:OutsideIpAddress,PSK:PreSharedKey}" \
  --output table
```

**원인 3: gcloud 인증 만료** — terraform이 GCP 자격증명을 못 찾는 경우

```bash
gcloud auth login       # 브라우저 로그인
# 또는 기업 환경(브라우저 차단):
gcloud auth print-access-token   # 토큰 확인만 → gcp-vpn-info.sh가 자동 설정
```

### NO_INCOMING_PACKETS (GCP 콘솔)

GCP가 IKE 패킷을 보내도 AWS가 응답하지 않는 상태. CGW IP가 GCP Interface 0 IP와 다른 경우.

```bash
gcloud compute vpn-tunnels list \
  --format="table(name,status,detailedStatus,peerIp)"
```

`peerIp`가 현재 배포된 VPN Outside IP와 일치하는지 확인.

### TGW 라우트 테이블에 GCP 경로 없음

```bash
# VPN 어태치먼트 propagation 확인 후 수동 등록
bash scripts/aws/ops/tgw-vpn-attach.sh
```

### terraform state 비어있음 (팀원 재실행 등)

`gcp-vpn-info.sh`가 자동으로 idempotent import → apply 처리. 별도 조작 불필요.

### GCS 접속 타임아웃 (Glue ETL)

TGW 라우트 테이블에 `10.50.0.0/24` 경로 확인 후 없으면:
```bash
bash scripts/aws/ops/tgw-vpn-attach.sh
```

---

## 주요 리소스

| 리소스 | 값 |
|--------|-----|
| GCP HA VPN Gateway | bookflow-aws-ha-vpn (asia-northeast1) |
| GCP HA VPN Interface 0 IP | 34.157.64.22 (고정) |
| GCP Cloud Router | bookflow-aws-cr (ASN 64514) |
| GCP VPC | bookflow-vpc |
| GCP Project | project-8ab6bf05-54d2-4f5d-b8d |
| AWS TGW BGP ASN | 64512 |
| terraform 디렉토리 | `infra/gcp/20-network-daily/` |

---

*작성: 2026-05-14 · 업데이트: 2026-05-18 · BookFlow V6.2*
*gcp-vpn-info.sh가 terraform 자동 적용 포함. 스크립트 2개로 VPN 구축 완료.*
