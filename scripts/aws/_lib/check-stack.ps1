# Stack 상태 확인
. (Join-Path $PSScriptRoot "common.ps1")

function Get-StackStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Name,
        [string]$Tier = "00"
    )
    $StackName = Get-StackName -Tier $Tier -Name $Name
    $status = aws cloudformation describe-stacks --stack-name $StackName --region $env:AWS_REGION --query 'Stacks[0].StackStatus' --output text 2>$null
    if ($LASTEXITCODE -ne 0) {
        return "NOT_FOUND"
    }
    return $status
}

function Show-AllStacks {
    Write-Step "BOOKFLOW Stack 전체 현황"
    aws cloudformation list-stacks --region $env:AWS_REGION `
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_IN_PROGRESS CREATE_IN_PROGRESS DELETE_IN_PROGRESS DELETE_FAILED UPDATE_ROLLBACK_COMPLETE `
        --query "StackSummaries[?starts_with(StackName, '$env:BOOKFLOW_STACK_PREFIX-')].[StackName,StackStatus,LastUpdatedTime]" `
        --output table
}
