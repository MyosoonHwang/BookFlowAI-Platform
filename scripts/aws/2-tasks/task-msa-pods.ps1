# BOOKFLOW · task-msa-pods · EKS Cluster + Node Group + Addons + endpoints-bookflow-ai
#   대상: 영헌 (EKS Pod 8종 개발)
#   전제: base-up.ps1 완료
#   추천: task-data.ps1 먼저 실행 (Pod 가 RDS · Redis · Secrets 사용)
#   소요: ~22분 (EKS Cluster 15 + Nodegroup 5 + Addons 2)
#   비용: ~$1.20/일 (EKS Control Plane $0.90 + Node Group t3.medium × 2 $0.30)

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-msa-pods · EKS Cluster + Node Group + endpoints ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 의존성 체크
if (-not (Test-Stack -Name "vpc-bookflow-ai" -Tier "10")) {
    Write-Err "Tier 10 VPC 미배포 · base-up.ps1 먼저 실행"; exit 1
}
if (-not (Test-Stack -Name "rds" -Tier "20")) {
    Write-Warn "RDS 미배포 · Pod 가 DB 접속 필요 시 task-data.ps1 먼저 권장"
}

# BookFlow AI VPC Endpoints (ECR pull · CW logs · Secrets 등 · Private subnet 에서 AWS 서비스 접근)
Deploy-Stack -Tier "10" -Name "endpoints-bookflow-ai" -Template "10-network-core/endpoints/endpoints-bookflow-ai.yaml"

# EKS Control Plane (15분 · 가장 오래)
Deploy-Stack -Tier "30" -Name "eks-cluster"             -Template "30-compute-cluster/eks-cluster.yaml"

# ALB Controller IRSA (OIDC 필요 → eks-cluster 후)
Deploy-Stack -Tier "30" -Name "eks-alb-controller-irsa" -Template "30-compute-cluster/eks-alb-controller-irsa.yaml"

# ESO IRSA (auth-pod 가 Secrets Manager 에서 Entra Client Secret 등 가져옴)
Deploy-Stack -Tier "30" -Name "eks-eso-irsa"            -Template "30-compute-cluster/eks-eso-irsa.yaml"

# Node Group (EC2 t3.medium × 1 · MaxSize 2 autoscale)
Deploy-Stack -Tier "40" -Name "eks-nodegroup" -Template "40-compute-runtime/eks-nodegroup.yaml"

# Core Addons (vpc-cni · kube-proxy · coredns · ebs-csi · pod-identity)
Deploy-Stack -Tier "40" -Name "eks-addons"    -Template "40-compute-runtime/eks-addons.yaml"

Write-Step "═══ task-msa-pods 완료 · K8s Pod/Ingress 는 CI/CD 가 apply ═══"
Write-Info  "kubeconfig: aws eks update-kubeconfig --name bookflow-eks --region $env:AWS_REGION"
