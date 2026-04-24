# BOOKFLOW · 매일 저녁 18:00 · 전체 destroy (base + 모든 task 자원)
#   영구 자원 (Tier 00) 는 제외 · 나머지 매일 destroy/create
#   역순 destroy (의존성 역방향)

. (Join-Path $PSScriptRoot "..\_lib\destroy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ 매일 저녁 · 전체 destroy ═══"

if (-not (Test-AwsCredentials)) {
    Write-Err "AWS 인증 실패"
    exit 1
}

# 현재 있는 stack 모두 찾아서 역순 destroy
# Tier prefix 순서: 60 → 50 → 40 → 30 → 20 → 10 (Tier 00은 영구)
$tierOrder = @('60', '50', '40', '30', '20', '10')
$prefix = $env:BOOKFLOW_STACK_PREFIX

foreach ($tier in $tierOrder) {
    $stacks = aws cloudformation list-stacks --region $env:AWS_REGION `
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE `
        --query "StackSummaries[?starts_with(StackName, '$prefix-$tier-')].StackName" --output json | ConvertFrom-Json

    foreach ($stackName in $stacks) {
        $name = $stackName -replace "^$prefix-$tier-", ""
        Write-Info "Destroy: $stackName"
        aws cloudformation delete-stack --stack-name $stackName --region $env:AWS_REGION
    }

    # 해당 tier stack 모두 delete 대기
    foreach ($stackName in $stacks) {
        aws cloudformation wait stack-delete-complete --stack-name $stackName --region $env:AWS_REGION 2>$null
    }
}

Write-Step "═══ destroy 완료 · 비용 $0 ═══"
Show-AllStacks
