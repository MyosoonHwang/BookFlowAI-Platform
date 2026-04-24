# BOOKFLOW AWS 공유 설정 (git 올라감 · 팀 전체 동일)
# 개인 override는 aws.local.ps1 (gitignored)

# ─── 리전 / 계정 ───
$env:AWS_REGION       = "ap-northeast-1"
$env:AWS_DEFAULT_REGION = "ap-northeast-1"

# 계정 ID는 민감 정보 아니지만 팀 공유용
# (실제 배포 시 aws.local.ps1에서 override 가능)
$env:BOOKFLOW_ACCOUNT_ID = "REPLACE_WITH_ACCOUNT_ID"

# ─── 프로젝트 네이밍 ───
$env:BOOKFLOW_PROJECT   = "bookflow"
$env:BOOKFLOW_STACK_PREFIX = "bookflow"     # CFN Stack 이름 prefix · bookflow-iam, bookflow-kms ...

# ─── GitHub ───
$env:BOOKFLOW_GITHUB_ORG  = "MyosoonHwang"
$env:BOOKFLOW_GITHUB_REPO = "BookFlowAI-Platform"

# ─── 경로 ───
$Script:BookflowRepoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$env:BOOKFLOW_REPO_ROOT    = $Script:BookflowRepoRoot
$env:BOOKFLOW_INFRA_ROOT   = Join-Path $Script:BookflowRepoRoot "infra\aws"
$env:BOOKFLOW_EXPORTS_DIR  = Join-Path $Script:BookflowRepoRoot "exports"
