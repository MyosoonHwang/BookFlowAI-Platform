# BOOKFLOW · 팀 협업 가이드 (GitHub Flow)

> Repo: https://github.com/MyosoonHwang/BookFlowAI-Platform
> V6.2 아키텍처 · 3인 팀 (영헌 · 민지 · 우혁)

> ⚠️ **Git/GitHub 처음이라면** → [GIT_BASICS.md](./GIT_BASICS.md) 먼저 읽기 (개념 · 용어 · 실습)
> 이 문서는 개념은 이해한 상태에서 보는 **실전 워크플로우 레퍼런스**.

## 브랜치 전략

| 브랜치 | 담당 | 역할 |
|---|---|---|
| `main` | 전체 | 통합 브랜치 (PR 리뷰 후 merge) |
| `aws` | 영헌 | AWS IaC · CodePipeline · Ansible (RDS GitOps) |
| `azure` | 민지 | Azure IaC · Logic Apps · Bicep 파이프라인 |
| `gcp` | 우혁 | GCP IaC · Vertex AI · Cloud Functions |

### 장수 브랜치 (long-lived branches)

- `aws`, `azure`, `gcp` 는 **프로젝트 끝날 때까지 계속 유지**. merge되어도 삭제 안 함.
- 본인 브랜치에서 계속 작업 → feature 단위로 PR → merge 후 같은 브랜치에서 다음 작업 이어감.
- feature branch 별도 생성 불필요 (3명이 각자 영역 분리돼 있어서 충돌 거의 없음).

### PR 단위 (feature 단위 점진적 PR)

**한 번에 몰아서 PR 하지 말 것** — 이유:
- aws/azure/gcp 브랜치가 main에서 오래 떨어져 있으면 마지막에 거대한 conflict
- 리뷰어가 100+ 파일 diff 한 번에 보면 제대로 리뷰 안 됨
- 진행률 가시화 어려움

**권장 PR 크기**: 2~3일치 작업 · 5~15 파일 · 하나의 논리적 단위 (예: "Tier 00 foundation", "NAT + Peering")

#### PR 단위 예시 (영헌 기준)

| # | PR 제목 | 변경 범위 |
|---|---|---|
| 1 | [AWS] Tier 00 foundation 완성 | IAM·KMS·S3·Secrets·ACM·R53·CloudTrail·CloudWatch |
| 2 | [AWS] Tier 20 VPC + Peering + Endpoints | 4 VPC + Peering 6 + Interface Endpoint 7 |
| 3 | [AWS] Tier 20 cross-cloud (TGW + VPN) | TGW 허브 + Attachment + Site-to-Site VPN × 2 + Customer GW |
| 4 | [AWS] Tier 20 NAT + Client VPN + ALB + WAF | NAT × 2 + Client VPN + Internal/External ALB + WAF |
| 5 | [AWS] Tier 30 compute-cluster | EKS · ECS · Ansible Control Node |
| 6 | [AWS] Tier 40 compute-runtime | EKS Nodegroup · ECS Services × 3 · Publisher ASG |
| 7 | [AWS] Tier 99 serverless + glue | SAM Lambda × 6 · Glue Catalog/Jobs |
| 8 | [AWS] CodePipeline 4종 | EKS · ECS · Lambda SAM · Publisher CodeDeploy |
| 9 | [AWS] Ansible (RDS GitOps) | playbooks · roles · sql |
| 10 | [AWS] 운영 스크립트 | start-day.sh · stop-day.sh · deploy-foundation.sh |

→ 민지/우혁도 유사한 사이즈로 분할

---

## PR 사이클 요약

```
[aws 브랜치 계속 유지 · 삭제 X]
  ↓ feature 1 작업 (예: Tier 00 foundation)
  ↓ commit + push
  ↓ main 최신 반영: git fetch origin && git merge origin/main
  ↓ GitHub 웹에서 PR 생성 (base: main, compare: aws)
민지/우혁 리뷰 → Approve
  ↓ Squash and merge 선택
  ↓ 로컬 정리: git checkout main && git pull → git checkout aws && git merge main
  ↓ feature 2 작업 시작 (같은 aws 브랜치에서)
  ↓ ... 반복
```

### 각 PR 사이클 체크리스트

- [ ] feature 1개 단위로 완료 (2~3일 분량)
- [ ] commit 메시지 prefix 규칙 준수 (`feat(aws):` 등)
- [ ] main 최신 merge 완료
- [ ] push 완료
- [ ] GitHub 웹에서 PR 생성 · 제목 · 설명 작성
- [ ] 다른 담당자 2명에게 리뷰 요청 (`@민지 @우혁`)
- [ ] Approve 받음
- [ ] **Squash and merge** 선택 (커밋 히스토리 1줄로)
- [ ] 로컬 main 최신화
- [ ] aws 브랜치에 main 다시 merge (다음 작업 전)

### 주의사항

- ❌ 브랜치 삭제하지 말 것 — `aws/azure/gcp` 는 계속 살아 있어야 함
- ❌ **PR 올린 상태에서 같은 브랜치에서 다음 feature 이어서 작업 하지 말 것** — 리뷰 복잡해짐. merge 기다리고 시작.
- ✅ PR 올린 후 추가 commit 필요하면 같은 브랜치에 push → PR에 자동 반영 (새 PR 안 만들어도 됨)
- ✅ 병렬로 여러 작업 해야 하면 aws 브랜치에서 또 다른 하위 브랜치 만들어도 OK (예: `aws/experiment-x`) — 보통 불필요

---

## 1. 최초 setup (각 담당자 1회만)

```bash
# 1-1. 작업 폴더 생성 (어디든 OK)
cd C:\Users\본인계정\Desktop
mkdir "kyobo project"
cd "kyobo project"

# 1-2. Clone
git clone https://github.com/MyosoonHwang/BookFlowAI-Platform.git
cd BookFlowAI-Platform

# 1-3. GitHub 인증 (VSCode 또는 터미널에서 한 번만)
# - VSCode: 우측 하단 "Sign in to GitHub" 클릭
# - 터미널: git 명령 실행 시 브라우저 자동 뜸 → GitHub 로그인

# 1-4. 본인 이름·이메일 설정 (commit에 기록됨)
git config --global user.name "김영헌"
git config --global user.email "본인@email.com"

# 1-5. 본인 작업 브랜치로 전환
git checkout aws        # 영헌
# git checkout azure    # 민지
# git checkout gcp      # 우혁
```

---

## 2. 매일 작업 시작 전 (필수!)

```bash
# main 최신 변경사항을 내 브랜치에 병합
git checkout aws              # 본인 브랜치
git fetch origin              # 원격 최신 정보 가져오기
git merge origin/main         # main 변경 반영
git push origin aws           # 내 브랜치 원격에도 반영
```

**충돌(conflict) 발생 시**:
1. VSCode에서 빨간 표시된 파일 열어서 "Accept Current/Incoming" 선택
2. `git add . && git commit -m "main과 동기화"`
3. `git push`

---

## 3. 일상 작업 흐름 (작업 → commit → push)

```bash
# 본인 브랜치에서 작업
git status                      # 변경된 파일 확인
git add infra/aws/...           # 특정 파일만 stage (안전)
# 또는 git add .                # 전체 stage (.gitignore는 자동 제외)

git commit -m "feat(aws): NAT Gateway CloudFormation 추가"
git push origin aws
```

### Commit 메시지 규칙

| prefix | 의미 |
|---|---|
| `feat(aws):` | 새 기능/자원 추가 |
| `fix(aws):` | 버그 수정 |
| `docs:` | 문서 수정 |
| `refactor(aws):` | 리팩토링 |
| `chore:` | 설정/기타 |

---

## 4. Pull Request (내 작업을 main에 merge 요청)

### 4-1. 웹브라우저에서 GitHub 접속

https://github.com/MyosoonHwang/BookFlowAI-Platform

### 4-2. 상단 "Pull requests" 탭 → "New pull request"

### 4-3. 양쪽 브랜치 선택

- **base**: `main` ← 병합 대상
- **compare**: `aws` ← 내 작업 브랜치

### 4-4. "Create pull request" 버튼 클릭

### 4-5. 제목·설명 작성 (예시)

```
제목: [AWS] NAT Gateway + VPC Peering 구축

설명:
## 변경 사항
- NAT Gateway × 2 (Multi-AZ)
- VPC Peering 6 connections (P1-P2 임시)
- Interface Endpoint 7종 단일 AZ

## 테스트
- [ ] aws cloudformation validate 통과
- [ ] start-day.sh 로컬 실행 성공

## 리뷰 요청
@민지 @우혁 확인 부탁합니다
```

### 4-6. "Create pull request" 최종 클릭

### 4-7. 다른 담당자들이 리뷰

- "Files changed" 탭에서 변경 라인에 댓글 달기
- "Review changes" → Approve / Request changes / Comment

### 4-8. 2명 Approve 받으면 "Merge pull request" 버튼 활성화

→ **Squash and merge** (커밋 히스토리 깔끔) 선택

---

## 5. PR merge 후 내 로컬 브랜치 정리

```bash
# 로컬 main 최신화
git checkout main
git pull origin main

# 내 작업 브랜치에 최신 main 반영 (다음 작업 위해)
git checkout aws
git merge main
git push origin aws
```

---

## 6. 다른 담당자 작업 잠깐 보고 싶을 때

```bash
git fetch origin
git checkout azure              # 민지 작업 상태로 전환
# (확인만 · 수정 금지)
git checkout aws                # 내 작업으로 복귀
```

---

## 7. 담당자별 작업 영역 (충돌 방지)

### 영헌 (`aws` 브랜치)
- `infra/aws/**`
- `cicd/codepipeline/**`
- `cicd/ansible/**` (RDS GitOps)
- `scripts/start-day.sh`, `stop-day.sh` (AWS 부분)

### 민지 (`azure` 브랜치)
- `infra/azure/**` (로컬 apply · `az deployment group create`)
- AWS의 Glue 스크립트 연관 (`cicd/ansible/roles/glue-scripts/*`)

### 우혁 (`gcp` 브랜치)
- `infra/gcp/**` (로컬 apply · `terraform apply` · GCS backend)

### 공통 (main에 직접 수정 금지 · PR 필수)
- `README.md`
- `docs/**`
- `.gitignore`

---

## 8. 긴급 상황 대처

```bash
# 실수로 중요 파일 삭제했을 때
git checkout HEAD -- 파일경로

# 아직 push 안 한 마지막 commit 취소
git reset --soft HEAD~1         # 변경 내용은 유지
git reset --hard HEAD~1         # 변경 내용도 삭제 (주의!)

# 이미 push한 commit 되돌리기 (새 commit으로 역행)
git revert <커밋해시>
git push

# main 브랜치에 실수로 push한 경우 (팀원에게 먼저 알림!)
# → 팀 회의 후 결정
```

---

## 9. VSCode 팁

- 좌측 **Source Control** 탭 (`Ctrl+Shift+G`)에서 GUI로 git 관리 가능
- 좌측 하단 브랜치 이름 클릭 → 브랜치 전환 GUI
- **GitHub Pull Requests and Issues** 확장 설치 시 PR도 VSCode 내에서 리뷰 가능
- `Ctrl+Shift+P` → **Git: Sync** 하면 pull + push 동시에

---

## 10. 자주 쓰는 명령어 치트시트

```bash
git status                      # 현재 상태
git log --oneline -10           # 최근 10개 커밋
git diff                        # 변경사항 보기
git diff --staged               # stage된 변경사항
git branch -a                   # 모든 브랜치
git stash                       # 작업 임시 저장
git stash pop                   # 임시 저장 복구
git remote -v                   # 원격 저장소 확인
```

---

## 11. 자동화 트리거 (참고)

### 🤖 자동화 (GHA + Ansible)

| 변경 위치 | 트리거 | 결과 |
|---|---|---|
| `cicd/ansible/roles/glue-scripts/**` push | GHA `glue-redeploy.yml` → OIDC → SSM → Ansible CN | Glue scripts S3 sync · Job dry-run |
| `cicd/ansible/sql/**` push · `playbooks/rds-*.yml` push | GHA `rds-redeploy.yml` → OIDC → SSM → Ansible CN | RDS 스키마 + 시드 + 권한 재적용 |
| `bookflow-apps` repo push (별도) | CodePipeline (EKS·ECS·Lambda·Publisher) | 앱 자동 배포 |

### 🖐️ 로컬 apply (자동화 안 함)

| 영역 | 명령 | 이유 |
|---|---|---|
| Azure Bicep (`infra/azure/**`) | `az deployment group create` | dev iteration 5배 빠름 · 실 운영 단계 없음 |
| GCP Terraform (`infra/gcp/**`) | `terraform apply` (GCS backend) | 동일 이유 · state 공유는 GCS backend로 해결 |

민지(Azure) / 우혁(GCP)은 본인 PC에서 직접 deploy/destroy 실행. git push는 **상태 기록**용이고 실제 배포는 로컬 CLI.
