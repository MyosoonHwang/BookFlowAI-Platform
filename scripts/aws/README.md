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

# AWS 자격 증명 설정
aws configure
# AWS Access Key ID: ...
# AWS Secret Access Key: ...
# Default region name: ap-northeast-1
# Default output format: json

# 개인 config 생성 (필요 시)
Copy-Item config\aws.local.ps1.example config\aws.local.ps1
# 수정: aws.local.ps1
```

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

## 스크립트 매트릭스

| 스크립트 | Tier | 언제 | 올리는 것 |
|---|---|---|---|
| `0-initial/full-cross-cloud-test.ps1` | 최초 1회 · 통합테스트 | Phase 1 검증 / Phase 3 통합테스트 | 전체 + Azure·GCP VPN + TGW |
| `1-daily/base-up.ps1` | 매일 아침 | 매일 09:00 | 00-foundation + 10-data + 20a-network-core + 30-cluster |
| `1-daily/base-down.ps1` | 매일 저녁 | 매일 18:00 | 전체 역순 destroy |
| `2-tasks/task-rds-seed.ps1` | 작업 | RDS 시드 작업 시 | (base 가정) + Ansible CN 트리거 |
| `2-tasks/task-msa-pods.ps1` | 작업 | MSA Pod 개발 | (base) + 40-eks-nodegroup |
| `2-tasks/task-auth-pod.ps1` | 작업 | auth-pod 개발 | (base + msa-pods) + 20b-nat + 20c-vpn-azure |
| `2-tasks/task-etl-streaming.ps1` | 작업 | ETL1 POS | (base) + 40-ecs-services (POS sim) + 99-sl(pos-ingestor) |
| `2-tasks/task-etl-batch.ps1` | 작업 | ETL2+3 | (base) + 99-sl (aladin·event·sns·spike) + 99-glue |
| `2-tasks/task-forecast.ps1` | 작업 | forecast-svc · Vertex 학습 | (base) + 20c-vpn-gcp + 99-sl(forecast-trigger) |
| `2-tasks/task-publisher.ps1` | 작업 | Publisher 앱 | (base) + 20b-alb-external + 20b-waf + 40-publisher-asg |
| `utils/show-cross-cloud-exports.ps1` | 유틸 | base-up 후 자동 | — (조회만) |

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
