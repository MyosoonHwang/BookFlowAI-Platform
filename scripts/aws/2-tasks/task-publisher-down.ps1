# BOOKFLOW · task-publisher-down · Publisher ASG · ECS inventory-api · WAF · ALB · peering destroy

. (Join-Path $PSScriptRoot "..\_lib\destroy-stack.ps1")

Write-Step "═══ task-publisher-down · Publisher 전체 destroy ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# Tier 40 (먼저 · ALB Target group reference 제거)
Remove-StackSafe -Tier "40" -Name "ecs-inventory-api"
Remove-StackSafe -Tier "40" -Name "publisher-asg"

# Tier 50 (WAF → ALB · WAF 가 ALB 참조)
Remove-StackSafe -Tier "50" -Name "waf"
Remove-StackSafe -Tier "50" -Name "alb-external"

# Tier 10 peering
Remove-StackSafe -Tier "10" -Name "peering-egress-data"

Write-Step "═══ task-publisher-down 완료 ═══"
