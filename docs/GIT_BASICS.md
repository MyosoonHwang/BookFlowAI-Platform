# 🐣 Git · GitHub 완전 초심자 가이드

> "Git/GitHub 처음이에요" 수준에서 시작.
> 이 문서 다 읽고 [TEAM_GUIDE.md](./TEAM_GUIDE.md)로 넘어가면 됨.

---

## 목차

- [0. Git · GitHub가 뭔데?](#0-git--github가-뭔데)
- [1. 필수 용어 10개 (외우지 말고 이해만)](#1-필수-용어-10개-외우지-말고-이해만)
- [2. 우리 팀 브랜치 구조 (중요!)](#2-우리-팀-브랜치-구조-중요)
- [3. 맨 처음 한 번만 (setup)](#3-맨-처음-한-번만-setup)
- [4. 작업 한 사이클 — A부터 Z까지 직접 따라하기](#4-작업-한-사이클--a부터-z까지-직접-따라하기)
- [5. 매일 아침 루틴](#5-매일-아침-루틴)
- [6. 충돌(conflict) 났을 때](#6-충돌conflict-났을-때)
- [7. 자주 하는 실수 & 살려내기](#7-자주-하는-실수--살려내기)
- [8. VSCode에서 버튼으로 하기 (명령어 싫을 때)](#8-vscode에서-버튼으로-하기-명령어-싫을-때)
- [9. 치트시트](#9-치트시트)

---

## 0. Git · GitHub가 뭔데?

### 문제 상황부터

우리 3명이 같은 폴더를 각자 고친다고 생각해보자.

```
영헌: "오늘 vpc.yaml 20줄 고쳤다"
민지: "나도 같은 파일 15줄 고쳤는데..."
우혁: "나도 만졌음ㅋ"
```

→ 카톡으로 파일 주고받으면 누구 버전이 최신인지 모름. 덮어쓰기 사고 남.

### Git (기트)

내 컴퓨터에 설치돼 있는 **"파일 변경 이력 관리 프로그램"**.
- "언제, 누가, 어느 줄을 고쳤는지" 전부 기록.
- 과거 상태로 언제든 복구 가능.
- MS Word의 "변경사항 추적" + 무한 Ctrl+Z 같은 거.

### GitHub (깃허브)

**Git으로 관리되는 파일을 웹에 올려서 팀과 공유하는 사이트**.
- 네이버 클라우드나 구글 드라이브의 개발자 버전.
- 우리 프로젝트는 여기 있음: https://github.com/MyosoonHwang/BookFlowAI-Platform

**비유**
| 일반 세상 | Git 세상 |
|---|---|
| 내 컴퓨터의 폴더 | 로컬 저장소 (local repo) |
| 구글 드라이브 공유 폴더 | GitHub 원격 저장소 (remote repo) |
| "파일 업로드" | `git push` |
| "파일 다운로드" | `git pull` |
| 문서의 저장 시점 | `git commit` (스냅샷 1개) |
| 평행 세계 (다른 버전 동시 작업) | 브랜치 (branch) |

---

## 1. 필수 용어 10개 (외우지 말고 이해만)

### 1. **repo (레포/저장소)**
프로젝트 폴더 하나. 우리는 `BookFlowAI-Platform` 이 repo.

### 2. **clone (클론)**
GitHub의 repo를 내 컴퓨터로 **처음 한 번** 복사해오는 것.
```bash
git clone https://github.com/MyosoonHwang/BookFlowAI-Platform.git
```

### 3. **commit (커밋)**
지금까지 고친 내용을 **"스냅샷 1장"**으로 저장. 메시지도 꼭 달아야 함.
- 비유: 게임 세이브 포인트
- 중요: commit은 **내 컴퓨터에만** 저장됨. 아직 GitHub에 안 올라간 상태.

### 4. **push (푸시)**
내 컴퓨터의 commit들을 GitHub에 **업로드**.
```bash
git push origin aws
```

### 5. **pull (풀)**
GitHub에 있는 최신 변경사항을 내 컴퓨터로 **다운로드**.
```bash
git pull origin main
```

### 6. **branch (브랜치)**
평행 세계. 같은 파일이 여러 버전으로 동시에 존재할 수 있음.
- `main` 브랜치 = 진짜 세계 (완성본)
- `aws` 브랜치 = 영헌의 실험실 (작업 중)

### 7. **checkout (체크아웃)**
브랜치를 **이동**. "지금 어느 평행 세계에 있을지" 선택.
```bash
git checkout aws        # aws 브랜치로 이동
git checkout main       # main 브랜치로 이동
```

### 8. **merge (머지)**
두 브랜치를 **합치기**. "내 실험실(aws) 결과를 진짜 세계(main)에 반영"
```bash
git merge main          # main의 변경사항을 현재 브랜치에 합침
```

### 9. **PR / Pull Request (풀 리퀘스트)**
GitHub에서 "**내 브랜치의 작업을 main에 합쳐주세요**"라고 제출하는 **요청서**.
- 카톡처럼 팀원이 검토 후 승인해야 실제로 합쳐짐.
- 리뷰 과정이 따라옴 (다른 팀원이 변경사항을 보고 OK/수정요청).

### 10. **conflict (충돌)**
같은 파일의 **같은 줄**을 나와 다른 사람이 다르게 고쳤을 때 나는 에러.
git이 "둘 중 뭐가 맞아?"라고 물어봄. → 사람이 직접 선택해야 함.

---

## 2. 우리 팀 브랜치 구조 (중요!)

```
              main (진짜 세계 · 완성본)
              │
      ┌───────┼───────┐
      │       │       │
    aws    azure     gcp
   (영헌)  (민지)    (우혁)
```

### 규칙

- **main 브랜치는 절대 직접 수정 안 함** — PR 통해서만 변경 허용
- **각자 자기 브랜치에서만 작업**
  - 영헌 = `aws` 브랜치
  - 민지 = `azure` 브랜치
  - 우혁 = `gcp` 브랜치
- 작업 완료 단위마다 → main에 PR 보내서 합침
- merge된 뒤에도 브랜치 계속 사용 (삭제 금지)

---

## 3. 맨 처음 한 번만 (setup)

### 3-1. 필요한 프로그램 설치

1. **Git 설치** (한번만)
   - Windows: https://git-scm.com/download/win → 다운로드 후 설치 (기본값으로 다 "Next")
   - 설치 확인: 터미널에서 `git --version` 치면 `git version 2.xx.x` 나와야 함

2. **VSCode 설치** (한번만)
   - https://code.visualstudio.com → 다운로드 후 설치

### 3-2. Git에 내 이름·이메일 등록 (한번만)

터미널 열고 (VSCode 안에서 `Ctrl+` 백틱 누르면 됨):

```bash
git config --global user.name "김영헌"
git config --global user.email "본인@email.com"
```

> 이 정보가 commit 찍을 때마다 "누가 수정했는지"로 기록됨.

### 3-3. 프로젝트 복사해오기 (clone)

```bash
# 1. 작업 폴더로 이동 (예: 바탕화면에 kyobo project 폴더 만들기)
cd C:\Users\본인계정\Desktop
mkdir "kyobo project"
cd "kyobo project"

# 2. 프로젝트 clone
git clone https://github.com/MyosoonHwang/BookFlowAI-Platform.git

# 3. 프로젝트 폴더로 들어가기
cd BookFlowAI-Platform
```

이제 `BookFlowAI-Platform` 폴더가 내 컴퓨터에 생김.

### 3-4. VSCode로 프로젝트 열기

```bash
code .       # 현재 폴더를 VSCode로 열기
```

또는 VSCode → File → Open Folder → `BookFlowAI-Platform` 선택.

### 3-5. GitHub 로그인

VSCode 좌측 사이드바의 **계정 아이콘** (또는 우측 하단) 클릭 → GitHub으로 로그인 → 브라우저에서 승인.

→ 이제 push/pull할 때 비밀번호 안 물어봄.

### 3-6. 내 브랜치로 이동

```bash
# 영헌인 경우
git checkout aws

# 민지인 경우
git checkout azure

# 우혁인 경우
git checkout gcp
```

확인:
```bash
git branch --show-current      # aws 혹은 azure 혹은 gcp 나와야 함
```

**여기까지 하면 셋업 끝. 이제 작업 가능.**

---

## 4. 작업 한 사이클 — A부터 Z까지 직접 따라하기

**시나리오**: 영헌이 aws 브랜치에서 NAT Gateway CloudFormation 템플릿을 추가하고 main에 반영.

### Step 1. 작업 시작 전 최신화

```bash
# 1. 내 브랜치에 있는지 확인
git branch --show-current     # aws 나와야 함

# 2. 원격(GitHub) 최신 정보 가져오기
git fetch origin

# 3. main의 최신 변경사항 내 브랜치로 반영
git merge origin/main

# 4. 원격에도 반영
git push origin aws
```

> 😐 **왜 이걸 매번 하냐?**
> 민지가 어제 main에 뭘 merge했으면, 내 aws 브랜치는 그걸 모르고 작업하게 됨. 나중에 내 PR 보낼 때 충돌 심해짐. **매일 아침 = 무조건 습관**.

### Step 2. 파일 수정

VSCode에서 `infra/aws/20-network-daily/nat-gateway.yaml` 파일 열고 내용 작성.

저장 (`Ctrl+S`).

### Step 3. 뭐 바뀌었는지 확인

터미널:
```bash
git status
```

예시 출력:
```
On branch aws
Changes not staged for commit:
  modified:   infra/aws/20-network-daily/nat-gateway.yaml
```

> "Changes not staged for commit" = "고친 건 있는데 아직 저장(commit) 안 했어"

```bash
git diff                      # 어떤 줄을 어떻게 고쳤는지 보기
```

### Step 4. 변경사항 스테이지 (stage)

commit할 파일 미리 "선택"하는 단계.

```bash
# 특정 파일만 (권장)
git add infra/aws/20-network-daily/nat-gateway.yaml

# 또는 모든 변경 파일
git add .
```

> 💡 **stage가 왜 필요함?** 여러 파일 고쳤는데 "이 3개만 이번 commit에 담고 싶어" 할 때 유용. 나중엔 `git add .` 써도 OK.

### Step 5. commit (스냅샷 1장 찍기)

```bash
git commit -m "feat(aws): NAT Gateway Multi-AZ CloudFormation 추가"
```

메시지 규칙:
- `feat(aws): ...` — 새 기능
- `fix(aws): ...` — 버그 수정
- `docs: ...` — 문서 수정
- `refactor(aws): ...` — 구조 개선

### Step 6. GitHub에 업로드 (push)

```bash
git push origin aws
```

→ GitHub의 aws 브랜치에 내 commit이 올라감. 아직 main엔 반영 안 됨.

### Step 7. GitHub 웹으로 이동해서 PR 만들기

1. 브라우저로 https://github.com/MyosoonHwang/BookFlowAI-Platform 접속
2. 상단 **Pull requests** 탭 클릭
3. 녹색 **New pull request** 버튼 클릭
4. 두 가지 브랜치 선택:
   - `base: main`     ← 합쳐질 목적지
   - `compare: aws`   ← 내 작업 브랜치
5. **Create pull request** 버튼 클릭
6. 제목 + 설명 작성:
   ```
   제목: [AWS] NAT Gateway Multi-AZ 추가

   설명:
   ## 변경 사항
   - Egress VPC public subnet에 NAT Gateway × 2 추가
   - Multi-AZ HA 구성

   ## 테스트
   - [ ] aws cloudformation validate-template 통과

   ## 리뷰 요청
   @민지 @우혁 확인 부탁합니다
   ```
7. **Create pull request** 버튼 최종 클릭

### Step 8. 리뷰 받기

- 민지/우혁이 PR 페이지에서 코드 확인
- "Files changed" 탭에서 각 줄에 댓글 달 수 있음
- 우측 **Reviewers** 섹션에서 Approve / Request changes 선택

### Step 9. merge (합치기)

2명 Approve 받으면 PR 페이지 하단에 녹색 **Merge pull request** 버튼 활성화.
- 드롭다운에서 **Squash and merge** 선택 (추천: 커밋 깔끔하게 1줄로)
- **Confirm squash and merge** 클릭 → 완료

→ 이 순간 main에 내 변경사항 반영됨!

### Step 10. 내 로컬도 최신화

main에 새 commit이 생겼으니 내 컴퓨터도 동기화:

```bash
# 1. main으로 이동해서 최신 받기
git checkout main
git pull origin main

# 2. 다시 aws 브랜치로 가서 main 반영
git checkout aws
git merge main
git push origin aws
```

이제 aws 브랜치도 main과 동기화됨. **다음 작업 사이클 시작 가능**.

---

## 5. 매일 아침 루틴

아침에 VSCode 켜자마자 터미널에:

```bash
git checkout aws              # 내 브랜치 (영헌 기준)
git fetch origin
git merge origin/main
git push origin aws
```

딱 이 4줄만 습관. **5초면 끝나는데 이거 안 하면 나중에 충돌로 30분 날림**.

---

## 6. 충돌(conflict) 났을 때

### 언제 발생?

- 내가 고친 줄을 누군가 이미 main에서 다르게 고쳐놓음
- git이 "어느 게 맞아?" 물어봄

### 증상

`git merge origin/main` 실행했을 때:
```
Auto-merging infra/aws/vpc.yaml
CONFLICT (content): Merge conflict in infra/aws/vpc.yaml
Automatic merge failed; fix conflicts and then commit the result.
```

### 해결법 (VSCode에서 · 제일 쉬움)

1. **좌측 Source Control 탭 (`Ctrl+Shift+G`) 열기**
2. **Merge Changes** 섹션에 빨간색 충돌 파일 보임
3. 파일 클릭하면 에디터에 이런 마크 뜸:
   ```yaml
   <<<<<<< HEAD
   Region: ap-northeast-1      # 내가 쓴 거
   =======
   Region: ap-northeast-2      # 민지가 main에 쓴 거
   >>>>>>> origin/main
   ```
4. 위에 **Accept Current / Accept Incoming / Accept Both / Compare** 버튼 중 선택:
   - **Accept Current** — 내 코드 유지 (HEAD 부분)
   - **Accept Incoming** — main 코드 수락
   - **Accept Both** — 둘 다 (주의: 문법 깨질 수 있음)
   - 직접 수정도 OK
5. 모든 충돌 해결되면 (빨간 줄 사라지면):
   ```bash
   git add .
   git commit               # 자동 메시지로 OK
   git push origin aws
   ```

### 포기하고 싶을 때

"아 나중에 할래":
```bash
git merge --abort           # merge 시작 전으로 롤백
```

---

## 7. 자주 하는 실수 & 살려내기

### ❓ commit 메시지 오타 냈어 (아직 push 안 함)

```bash
git commit --amend -m "새 메시지"
```

### ❓ 실수로 파일 삭제했어 (아직 commit 안 함)

```bash
git checkout HEAD -- 파일경로
```

### ❓ 방금 한 commit 취소하고 싶어 (아직 push 안 함)

```bash
# 변경 내용은 유지 (파일 그대로, commit만 취소)
git reset --soft HEAD~1

# 변경 내용까지 삭제 (주의: 되돌릴 수 없음)
git reset --hard HEAD~1
```

### ❓ 실수로 main 브랜치에 commit하고 push했어

**팀원에게 먼저 카톡**. 되돌리는 법:
```bash
git revert <커밋해시>       # 새 commit으로 "역행"
git push origin main
```

### ❓ 브랜치 잘못 만들어서 commit 했어

```bash
# 지금 commit을 aws 브랜치로 옮기기
git log -1                  # 마지막 commit 해시 확인 (abc1234)
git checkout aws
git cherry-pick abc1234     # 그 commit 가져오기

# 원래 잘못된 브랜치에서 그 commit 제거
git checkout 잘못된브랜치
git reset --hard HEAD~1
```

### ❓ 지금 작업 중인데 다른 브랜치로 가봐야 해

```bash
git stash                   # 현재 작업 임시 보관
git checkout azure          # 다른 브랜치로
# ... 확인 후 ...
git checkout aws            # 내 브랜치 복귀
git stash pop               # 보관했던 작업 복구
```

### ❓ push했는데 "rejected" 에러 남

내가 보지 못한 변경이 원격에 있음:
```bash
git pull origin aws         # 먼저 받고
git push origin aws         # 다시 push
```

---

## 8. VSCode에서 버튼으로 하기 (명령어 싫을 때)

### 좌측 Source Control 탭 (`Ctrl+Shift+G`)

여기서 대부분 GUI로 가능:

| 내가 하려는 것 | VSCode 버튼 |
|---|---|
| 파일 stage (add) | 변경 파일 옆 **+** 클릭 |
| 모두 stage | **Changes** 헤더 옆 **+** |
| commit | 상단 메시지 박스에 입력 → **✓ Commit** 버튼 |
| push | 좌측 하단 브랜치 이름 클릭 → **Sync** (pull+push 동시) |
| 브랜치 전환 | 좌측 하단 브랜치 이름 클릭 → 목록에서 선택 |
| 충돌 해결 | 충돌 파일 열면 상단에 버튼 자동 표시 |

### 추천 확장

VSCode 확장 탭에서 설치:
- **GitHub Pull Requests and Issues** — VSCode 안에서 PR 리뷰/생성 가능
- **GitLens** — 각 줄 누가 고쳤는지 보여줌 (blame)

---

## 9. 치트시트

### 매일 쓰는 것

```bash
git status                    # 지금 뭔 상태야?
git diff                      # 뭘 고쳤어?
git add <파일>                # 이 파일 commit에 담을래
git commit -m "메시지"         # 스냅샷 저장
git push origin 내브랜치       # GitHub에 업로드
git pull origin main          # main 최신 받기
git log --oneline -10         # 최근 commit 10개 보기
```

### 가끔 쓰는 것

```bash
git branch                    # 내 로컬 브랜치 목록
git branch -a                 # 원격 포함 전체
git checkout <브랜치>          # 브랜치 이동
git fetch origin              # 원격 정보만 가져오기 (merge 안 함)
git merge <브랜치>             # 현재 브랜치에 합치기
git stash                     # 작업 임시 저장
git stash pop                 # 임시 저장 복구
```

### 위급 상황

```bash
git merge --abort             # merge 중단
git reset --hard HEAD~1       # 마지막 commit 완전 삭제 (위험)
git revert <해시>             # commit 역행 (안전)
git checkout HEAD -- 파일     # 파일을 마지막 commit 상태로
```

---

## 🎯 이 가이드 다 이해했으면

→ [TEAM_GUIDE.md](./TEAM_GUIDE.md) 로 넘어가자. 실전 PR 흐름 + 우리 팀 규칙.

## 📺 영상 학습 추천

- **얄코 "제대로 파는 Git & GitHub"** — 섹션 1~4가 기초
  - https://www.youtube.com/watch?v=1I3hMwQU6GU
- **생활코딩 "지옥에서 온 Git"** — 원리 깊이 이해
  - https://www.youtube.com/playlist?list=PLuHgQVnccGMA8iwZwrGyNXCGy2LAAsTXk
- **드림코딩 "깃, 깃허브 6분 정리"** — 속성 감 잡기
  - https://www.youtube.com/watch?v=lPrxhA4PLoA

---

## 💡 팁: 처음엔 무조건 겁먹지 마라

- git은 **잘못해도 대부분 복구 가능**함 (commit만 했으면)
- 제일 위험한 건 `git reset --hard` 와 `git push --force` — 이 두 개만 조심
- 모르겠으면 터미널에서 `git status` 먼저 치고 상태 확인
- 안되면 팀원한테 화면 공유하고 도움 요청 (창피한 거 아님 · 고수들도 헷갈려함)
