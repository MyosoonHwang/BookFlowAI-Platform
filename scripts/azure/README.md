# Azure 배포 스크립트 (민지 담당)

> 실행 환경: Git Bash (Windows) · `az` CLI · `az bicep`
> 작업 디렉토리: `bookflow-azure-iac/` (modules/ · scripts/ · parameters/ 가 있는 폴더)

---

## 디렉토리 구조

```
bookflow-azure-iac/
├── modules/
│   ├── identity.bicep        # 관리 ID
│   ├── nsg.bicep             # NSG
│   ├── vnet.bicep            # VNet + 서브넷
│   ├── monitor.bicep         # Log Analytics
│   ├── keyvault.bicep        # Key Vault (RBAC 포함)
│   ├── function.bicep        # Storage + ASP + Function App
│   ├── eventgrid.bicep       # Event Grid System Topic
│   ├── logicapp.bicep        # Logic Apps × 2
│   ├── vpn.bicep             # VPN Gateway + PIP
│   ├── vpn-connection.bicep  # VPN Connection (AWS 연결용)
│   └── ...
├── parameters/
│   └── dev.json              # 공통 파라미터
├── scripts/
│   ├── deploy-all.sh         ← 전체 배포
│   ├── cleanup-all.sh        ← 전체 삭제 (리소스 그룹 포함)
│   ├── cleanup-selective.sh  ← 선택적 삭제 (Entra·PIP 보존)
│   ├── deploy-vpn.sh         ← VPN Gateway 단독 배포
│   ├── vpn-connect.sh        ← VPN Connection 생성 (AWS 연결)
│   ├── entra-setup.sh        ← Entra ID 앱 등록 (최초 1회)
│   ├── day1-deploy.sh        ← 1일차 단계별 배포 (레거시)
│   ├── day1-cleanup.sh       ← 1일차 리소스 정리 (레거시)
│   └── test-connectivity.sh  ← VPN 연결 후 통신 검증
└── functions/
    └── sync-secret/          # Function App 코드 (Python)
```

---

## 스크립트 매트릭스

| 스크립트 | 역할 | 실행 시점 | Entra 보존 | PIP 보존 | RG 유지 |
|---|---|---|---|---|---|
| `deploy-all.sh` | 전체 배포 (Stack 1~6) | 실습 시작 | — | — | — |
| `cleanup-all.sh` | 전체 삭제 | 완전 초기화 시 | ❌ | ❌ | ❌ |
| `cleanup-selective.sh` | 선택 삭제 | 비용 절감 시 | ✅ | ✅ | ✅ |
| `deploy-vpn.sh` | VPN Gateway 단독 배포 | VPN만 재배포 시 | — | — | — |
| `vpn-connect.sh` | VPN Connection 생성 | AWS 팀 준비 후 | — | — | — |
| `entra-setup.sh` | Entra 앱 등록 | 최초 1회 | — | — | — |

---

## 일상 사용법

### 실습 시작 (전체 배포)

```bash
cd bookflow-azure-iac
bash scripts/deploy-all.sh
```

### 실습 종료 (비용 절감 · Entra·PIP 보존)

```bash
bash scripts/cleanup-selective.sh
```

### 완전 초기화 (모든 것 처음부터)

```bash
bash scripts/cleanup-all.sh
```

---

## deploy-all.sh 상세

### 역할
Stack 1~6을 순서대로 배포. 각 Stack은 이미 배포된 경우 자동 스킵 (ARM 이력 기반).

### Stack 배포 순서

| Stack | 이름 | Bicep | 소요시간 |
|---|---|---|---|
| 1 | Foundation | identity · nsg · monitor · vnet | ~3분 |
| 2 | Security | keyvault | ~1분 |
| 3 | Compute | function | ~2분 |
| 4 | Integration | eventgrid | ~1분 |
| 5 | Automation | logicapp | ~1분 |
| 6 | Network | vpn | **30~45분** |

### 주요 동작

- **문법 검사**: 각 Bicep을 `az bicep build`로 사전 검증
- **배포 검증**: `az deployment group validate`로 Azure 사전 검증
- **Key Vault 자동 복구**: soft-delete 상태인 `kv-bookflow` 감지 시 `az keyvault recover` 자동 실행
- **스킵 로직**: ARM 배포 이력에서 `Succeeded` 확인 → 이미 완료된 Stack은 건너뜀

### 실행 예시

```bash
bash scripts/deploy-all.sh

# 구독 확인 후 Enter
# VPN Gateway 배포 전 Enter (30~45분 소요 안내)
# 완료 후 AWS 팀 전달값 출력
```

### 완료 후 출력값 (AWS 팀 전달)

```
Active 공인 IP:  xxx.xxx.xxx.xxx   ← pip-bookflow-vpngw-active
Standby 공인 IP: xxx.xxx.xxx.xxx   ← pip-bookflow-vpngw-standby
BGP ASN:         65001
BGP Peering IP:  172.16.1.x
```

---

## cleanup-all.sh 상세

### 역할
리소스 그룹 전체 삭제 + Entra ID 앱·그룹 삭제. **PIP 포함 모든 것 삭제.**

### 삭제 대상

| 단계 | 대상 | 비고 |
|---|---|---|
| 1 | Resource Group `rg-bookflow` | 하위 리소스 전체 포함 |
| 2 | Key Vault soft-delete 상태 확인 | 90일 자동 만료 안내 |
| 3 | Entra ID 앱 `BookFlow-Internal` | App ID 삭제 |
| 4 | Entra ID 그룹 4개 | 멤버십 초기화 |

### ⚠ 주의

```
- PIP 2개 삭제됨 → 재배포 시 새 IP 발급 → AWS Customer Gateway 재설정 필요
- Entra 앱 삭제됨 → 재배포 시 새 App ID → AWS 팀에 재전달 필요
- Key Vault는 Purge Protection으로 삭제 불가 → 90일간 soft-delete 유지
  단, deploy-all.sh 재실행 시 자동 복구됨 (시크릿 보존)
```

### 실행 예시

```bash
bash scripts/cleanup-all.sh

# 삭제 대상 목록 확인 후 Enter
# 구독 확인 후 Enter
# 약 5~15분 소요
```

---

## cleanup-selective.sh 상세

### 역할
**Entra ID 앱·그룹과 PIP 2개를 보존**하고 나머지 재배포 가능 자원만 삭제.
리소스 그룹은 유지. 비용 절감이 목적.

### 삭제 순서 (의존성 역순)

| 단계 | 자원 | 비고 |
|---|---|---|
| 1 | VPN Connection | VPN Gateway 삭제 전 필수 |
| 2 | Local Network Gateway | |
| 3 | VPN Gateway | **PIP는 유지** |
| 4 | Logic Apps × 2 | |
| 5 | Event Grid | |
| 6 | Function App | |
| 7 | App Service Plan | Function App 삭제 후 |
| 8 | Storage Account | |
| 9 | Key Vault | soft-delete 전환 (시크릿 보존) |
| 10 | Log Analytics | |
| 11 | VNet | VPN Gateway 삭제 후 |
| 12 | NSG × 2 | VNet 삭제 후 |
| 13 | 관리 ID × 2 | |
| 14 | ARM 배포 이력 삭제 | **deploy-all.sh 재실행 시 skip 방지** |

### 핵심 동작: ARM 이력 삭제 (14단계)

`deploy-all.sh`의 스킵 로직은 ARM 배포 이력 기반. 리소스 그룹을 유지하면 이력이 남아 재배포 시 모든 Stack이 스킵됨.
→ `cleanup-selective.sh`가 9개 배포 이력을 `az deployment group delete`로 자동 제거.

```
삭제 이력: identity-deploy · nsg-deploy · monitor-deploy · vnet-deploy
           keyvault-deploy · function-deploy · eventgrid-deploy
           logicapp-deploy · vpn-deploy
```

### 실행 예시

```bash
bash scripts/cleanup-selective.sh

# 보존/삭제 대상 확인 후 Enter
# 구독 확인 후 Enter
# VPN Gateway 삭제 10~20분 포함 총 약 15~25분 소요
# 완료 후 PIP IP · Entra App ID 보존 확인 출력
```

---

## 권장 사이클

### 비용 최적화 반복 사이클 (Entra·PIP 보존)

```
bash scripts/deploy-all.sh         # 실습 시작
        ↓ (실습 종료)
bash scripts/cleanup-selective.sh  # 비용 절감 (PIP·Entra 보존)
        ↓ (다음 실습)
bash scripts/deploy-all.sh         # Key Vault 자동 복구 포함 재배포
```

### VPN만 내릴 때

```bash
# VPN Gateway만 삭제 (PIP 유지, IP 불변)
az network vnet-gateway delete \
  --resource-group rg-bookflow \
  --name vpngw-bookflow

# VPN 재배포
bash scripts/deploy-vpn.sh
```

---

## 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| `unrecognized arguments: identity-deploy` | `validate`에 `--name` 전달됨 | deploy-all.sh validate_deployment 함수 확인 |
| 모든 Stack이 스킵됨 | ARM 이력 미삭제 후 재배포 | `cleanup-selective.sh` 14단계 실행 여부 확인 |
| Key Vault 배포 실패 `already exists in deleted state` | soft-delete 복구 안 됨 | deploy-all.sh 내 복구 블록 동작 확인 |
| VPN Gateway 배포 실패 `zones conflict` | 기존 PIP zones 불일치 | `deploy-vpn.sh` 2단계 PIP zones 정리 블록 자동 처리 |
| Logic App 디자이너 오류 `Incomplete information` | Bicep 커넥터 정의 불완전 | Portal에서 액션 삭제 후 새로 추가 (README 3단계 참고) |

---

## 배포 전 체크리스트

```
□ az account show 로 올바른 구독 확인
□ 작업 디렉토리가 bookflow-azure-iac/ 인지 확인
  (modules/ · scripts/ · parameters/ 가 보여야 함)
□ dev.json 의 securityAdminObjectId 입력 여부 확인
□ VPN Gateway 배포 시 30~45분 여유 확보
```
