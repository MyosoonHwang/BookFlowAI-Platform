# BOOKFLOW · task-msa-pods-down · EKS · Nodegroup · Addons · IRSA · endpoints · peering destroy
#   순서: Tier 40 (Addons + Nodegroup) → Tier 30 (IRSA + Cluster) → Tier 10 (peering + endpoints)
#   주의: Pod (K8s) 는 별도 (CI/CD 가 관리 · K8s 자원은 EKS 삭제 시 자동 사라짐)

. (Join-Path $PSScriptRoot "..\_lib\destroy-stack.ps1")

Write-Step "═══ task-msa-pods-down · EKS 전체 destroy ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# Tier 40 (Pod runtime)
Remove-StackSafe -Tier "40" -Name "eks-addons"
Remove-StackSafe -Tier "40" -Name "eks-nodegroup"

# Tier 30 (IRSA + EKS Cluster)
Remove-StackSafe -Tier "30" -Name "eks-eso-irsa"
Remove-StackSafe -Tier "30" -Name "eks-alb-controller-irsa"
Remove-StackSafe -Tier "30" -Name "eks-cluster"

# Tier 10 (peering + endpoints)
Remove-StackSafe -Tier "10" -Name "peering-bookflow-ai-egress"
Remove-StackSafe -Tier "10" -Name "peering-bookflow-ai-data"
Remove-StackSafe -Tier "10" -Name "endpoints-bookflow-ai"

Write-Step "═══ task-msa-pods-down 완료 ═══"
