# aws cloudformation delete-stack 래퍼
. (Join-Path $PSScriptRoot "common.ps1")

function Remove-StackSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Name,
        [string]$Tier = "00",
        [switch]$Wait = $true
    )

    $StackName = Get-StackName -Tier $Tier -Name $Name
    Write-Step "Destroy: $StackName"

    # 존재 확인
    $exists = aws cloudformation describe-stacks --stack-name $StackName --region $env:AWS_REGION 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Stack 없음 · skip: $StackName"
        return
    }

    aws cloudformation delete-stack --stack-name $StackName --region $env:AWS_REGION
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Destroy 요청 실패: $StackName"
        throw "Destroy failed"
    }

    if ($Wait) {
        Write-Info "Delete 완료 대기..."
        aws cloudformation wait stack-delete-complete --stack-name $StackName --region $env:AWS_REGION 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Destroy 완료: $StackName"
        } else {
            Write-Warn "Destroy wait 타임아웃 또는 실패 · 콘솔 확인 필요: $StackName"
        }
    } else {
        Write-Info "Destroy 진행 중 (wait 생략): $StackName"
    }
}
