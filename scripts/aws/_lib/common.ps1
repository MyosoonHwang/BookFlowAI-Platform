# BOOKFLOW AWS 공용 함수 (모든 스크립트가 dot-source 해서 사용)
# 사용법: 각 스크립트 상단에 `. $PSScriptRoot\..\_lib\common.ps1`

$ErrorActionPreference = 'Stop'

# ─── config 로드 (공유 + 개인 override) ───
$Script:ConfigDir = Join-Path (Split-Path $PSScriptRoot -Parent) "config"
. (Join-Path $Script:ConfigDir "aws.ps1")

$LocalConfig = Join-Path $Script:ConfigDir "aws.local.ps1"
if (Test-Path $LocalConfig) {
    . $LocalConfig
}

# ─── 로깅 함수 ───
function Write-Info  { Write-Host "ℹ  $args" -ForegroundColor Cyan }
function Write-Success { Write-Host "✅ $args" -ForegroundColor Green }
function Write-Warn  { Write-Host "⚠  $args" -ForegroundColor Yellow }
function Write-Err   { Write-Host "❌ $args" -ForegroundColor Red }
function Write-Step  { Write-Host "`n▶ $args" -ForegroundColor Magenta }

# ─── AWS 자격증명 / 계정 확인 ───
function Test-AwsCredentials {
    try {
        $identity = aws sts get-caller-identity 2>$null | ConvertFrom-Json
        if ($null -eq $identity) { return $false }
        Write-Info "AWS 계정: $($identity.Account) · IAM: $($identity.Arn)"
        return $true
    } catch {
        Write-Err "AWS 자격 증명 실패 · aws configure 실행하거나 AWS_PROFILE 설정"
        return $false
    }
}

# ─── Stack 이름 helpers ───
function Get-StackName {
    param([string]$Tier, [string]$Name)
    return "$env:BOOKFLOW_STACK_PREFIX-$Tier-$Name"
}

# ─── 공용 deploy 래퍼 (deploy-stack.ps1에 구현) ───
# 각 스크립트에서 직접 쓰지 말고 deploy-stack.ps1 을 dot-source

Write-Info "common.ps1 로드 완료 · Region=$env:AWS_REGION · Project=$env:BOOKFLOW_PROJECT"
