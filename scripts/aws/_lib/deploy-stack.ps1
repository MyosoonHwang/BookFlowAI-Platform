# aws cloudformation deploy 래퍼
# Dot-source: `. $PSScriptRoot\..\_lib\deploy-stack.ps1`
# 사용: Deploy-Stack -Name "iam" -Template "00-foundation/iam.yaml"

. (Join-Path $PSScriptRoot "common.ps1")

function Deploy-Stack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Name,             # 예: "iam" → bookflow-00-iam
        [Parameter(Mandatory=$true)] [string]$Template,         # 예: "00-foundation/iam.yaml" (infra/aws/ 기준 상대)
        [string]$Tier = "00",                                   # 예: "00", "10", "20a"
        [hashtable]$Parameters = @{},                           # 예: @{ GitHubRepo = "..." }
        [string[]]$Capabilities = @("CAPABILITY_NAMED_IAM"),
        [switch]$Wait = $true
    )

    $StackName = Get-StackName -Tier $Tier -Name $Name
    $TemplatePath = Join-Path $env:BOOKFLOW_INFRA_ROOT $Template

    if (-not (Test-Path $TemplatePath)) {
        Write-Err "Template 파일 없음: $TemplatePath"
        throw "Template not found"
    }

    Write-Step "Deploy: $StackName ← $Template"

    # Parameter 변환 (hashtable → CLI 인자)
    $ParamArgs = @()
    if ($Parameters.Count -gt 0) {
        $ParamArgs += "--parameter-overrides"
        foreach ($key in $Parameters.Keys) {
            $ParamArgs += "$key=$($Parameters[$key])"
        }
    }

    # Deploy
    $cmd = @(
        "cloudformation", "deploy",
        "--stack-name", $StackName,
        "--template-file", $TemplatePath,
        "--capabilities", $Capabilities,
        "--region", $env:AWS_REGION,
        "--no-fail-on-empty-changeset"
    ) + $ParamArgs

    aws @cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Deploy 실패: $StackName"
        throw "Deploy failed"
    }

    Write-Success "Deploy 완료: $StackName"
}

# ─── Stack Outputs 조회 ───
function Get-StackOutputs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Name,
        [string]$Tier = "00"
    )
    $StackName = Get-StackName -Tier $Tier -Name $Name
    $result = aws cloudformation describe-stacks --stack-name $StackName --region $env:AWS_REGION --query 'Stacks[0].Outputs' | ConvertFrom-Json
    return $result
}
