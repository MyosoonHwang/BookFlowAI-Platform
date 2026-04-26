# BOOKFLOW · 매일 저녁 18:00 · 전체 destroy (base + 모든 task 자원)
#   영구 자원 (Tier 00) 는 제외 · 나머지 매일 destroy/create
#   역순 destroy (의존성 역방향 · within-tier 명시 순서)

. (Join-Path $PSScriptRoot "..\_lib\destroy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ 매일 저녁 · 전체 destroy ═══"

if (-not (Test-AwsCredentials)) {
    Write-Err "AWS 인증 실패"
    exit 1
}

# Within-tier destroy 순서 (의존성 가장 깊은 것부터 · stack 이름 끝부분만)
#   각 tier 안에서 import 가 가장 많은 stack (leaf) 먼저 → base 가 되는 stack (vpc 등) 마지막
$tierStacks = [ordered]@{
    '60' = @('client-vpn', 'vpn-site-to-site', 'tgw')
    '50' = @('waf', 'alb-external', 'nat-gateway')
    '40' = @(
        'ecs-online-sim', 'ecs-offline-sim', 'ecs-inventory-api',
        'publisher-asg',
        'eks-addons', 'eks-nodegroup'
    )
    '30' = @(
        'eks-eso-irsa', 'eks-alb-controller-irsa', 'eks-cluster',
        'ansible-node', 'ecs-cluster'
    )
    '20' = @('kinesis', 'redis', 'rds')
    '10' = @(
        # peerings 가장 먼저 (VPC 두 개씩 사용)
        'peering-bookflow-ai-data', 'peering-bookflow-ai-egress',
        'peering-egress-data', 'peering-sales-data-egress', 'peering-ansible-data',
        # endpoints (VPC + SG 사용)
        'endpoints-bookflow-ai', 'endpoints-sales-data', 'endpoints-ansible',
        # route53 (Private Hosted Zone · VPC association)
        'route53',
        # customer-gateway (VPC 무관)
        'customer-gateway',
        # vpc-* 마지막
        'vpc-bookflow-ai', 'vpc-sales-data', 'vpc-egress', 'vpc-data', 'vpc-ansible'
    )
}

# Tier 99 (Glue + Lambdas) 는 별도 처리 · Tier 10/20/30 import 사용
# Tier 99 가 가장 먼저 destroy (다른 tier 가 99 의 export 안 씀)
Write-Info "Tier 99 (Glue + Serverless) destroy 먼저"
Remove-StackSafe -Tier "99" -Name "step-functions"
Remove-StackSafe -Tier "99" -Name "glue-catalog"
Remove-StackSafe -Tier "99" -Name "lambdas"

# Tier 60 → 10 순서로 destroy (명시 순서)
foreach ($tier in $tierStacks.Keys) {
    Write-Info "─── Tier $tier destroy ───"
    foreach ($name in $tierStacks[$tier]) {
        Remove-StackSafe -Tier $tier -Name $name
    }
}

# 명시 안 된 stack 잡기 (수동 생성 등) · 안전장치
Write-Info "─── Orphan stack 검색 (명시 순서 외) ───"
$prefix = $env:BOOKFLOW_STACK_PREFIX
$allStacks = aws cloudformation list-stacks --region $env:AWS_REGION `
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE ROLLBACK_COMPLETE DELETE_FAILED IMPORT_COMPLETE `
    --query "StackSummaries[?starts_with(StackName, '$prefix-') && !starts_with(StackName, '$prefix-00-')].StackName" `
    --output json | ConvertFrom-Json

if ($allStacks -and $allStacks.Count -gt 0) {
    Write-Warn "남은 stack $($allStacks.Count) 개 발견 (명시 순서 외 · 직접 destroy 시도):"
    foreach ($stackName in $allStacks) {
        Write-Info "  Destroy orphan: $stackName"
        aws cloudformation delete-stack --stack-name $stackName --region $env:AWS_REGION
    }
    foreach ($stackName in $allStacks) {
        aws cloudformation wait stack-delete-complete --stack-name $stackName --region $env:AWS_REGION
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "  Destroy 실패 또는 타임아웃: $stackName · 콘솔 확인 필요"
        }
    }
} else {
    Write-Success "Orphan stack 없음 · clean"
}

Write-Step "═══ destroy 완료 · 비용 $0 (Tier 00 제외) ═══"
Show-AllStacks
