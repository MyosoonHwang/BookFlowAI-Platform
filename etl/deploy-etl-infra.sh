#!/usr/bin/env bash
# deploy-etl-infra.sh
# One-shot ETL infrastructure deploy: s3-import -> base-up -> task-data -> task-etl-streaming
#
# Deploy order:
#   0. s3      : bookflow-00-s3 (S3 buckets with Outputs)
#   1. base-up : Tier 10 (3 VPCs) + Tier 30 (ECS cluster)
#   2. task-data : Tier 20 (RDS + Redis + Kinesis)
#   3. task-etl-streaming : Tier 10 endpoints + Tier 40 ECS sims
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="py ${REPO_ROOT}/scripts/aws/bookflow.py"
REGION="${AWS_REGION:-ap-northeast-1}"
PROJECT="bookflow"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "================================================"
echo " BookFlow ETL Infrastructure Deploy"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo " Account : ${ACCOUNT_ID}"
echo " ECR     : ${ECR_REGISTRY}"
echo "================================================"

# Step 0: S3 버킷 생성 (없으면 생성, 있으면 스킵)
echo ""
echo "[0/4] S3 buckets (create if missing)..."
for BUCKET in \
  "${PROJECT}-raw-${ACCOUNT_ID}" \
  "${PROJECT}-mart-${ACCOUNT_ID}" \
  "${PROJECT}-cp-artifacts-${ACCOUNT_ID}" \
  "${PROJECT}-glue-scripts-${ACCOUNT_ID}" \
  "${PROJECT}-tf-state-${ACCOUNT_ID}"; do

  if aws s3api head-bucket --bucket "${BUCKET}" --region "${REGION}" 2>/dev/null; then
    echo "  OK s3://${BUCKET} exists"
  else
    echo "  Creating s3://${BUCKET}..."
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
    aws s3api put-public-access-block \
      --bucket "${BUCKET}" \
      --region "${REGION}" \
      --public-access-block-configuration \
      '{"BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true}'
    aws s3api put-bucket-versioning \
      --bucket "${BUCKET}" \
      --region "${REGION}" \
      --versioning-configuration Status=Enabled
    echo "  OK s3://${BUCKET} created"
  fi
done

# Step 1: base-up (VPCs + ECS cluster)
echo ""
echo "[1/3] base-up (Tier 10 VPCs + Tier 30 ECS cluster)..."
${SCRIPT} base-up
echo "  OK base-up complete"

# Step 2: task-data (RDS + Redis + Kinesis)
echo ""
echo "[2/3] task-data (RDS + Redis + Kinesis)..."
${SCRIPT} task data
echo "  OK task-data complete"

# Step 3: ECR image build & push (required before ECS sims start)
echo ""
echo "[3/4] ECR image build & push (online-sim / offline-sim)..."
aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

for SIM in online-sim offline-sim; do
  IMAGE="${ECR_REGISTRY}/${PROJECT}/${SIM}:latest"
  echo "  -> ${SIM} build..."
  docker build -t "${IMAGE}" "${REPO_ROOT}/ecs-sims/${SIM}"
  docker push "${IMAGE}"
  echo "  OK ${IMAGE} pushed"
done

# Step 4: task-etl-streaming (endpoints + ECS sims)
echo ""
echo "[4/4] task-etl-streaming (VPC endpoints + ECS online/offline-sim)..."
${SCRIPT} task etl-streaming
echo "  OK task-etl-streaming complete"

echo ""
echo "================================================"
echo " Deploy Complete"
echo " - Tier 10: vpc-sales-data / vpc-egress / vpc-data / vpc-bookflow-ai"
echo " -          endpoints-sales-data (ECR/Kinesis/CWLogs/S3)"
echo " - Tier 20: RDS / Redis / Kinesis"
echo " - Tier 30: ECS cluster (bookflow-ecs)"
echo " - ECR   : online-sim / offline-sim images pushed
 - Tier 40: ECS online-sim / offline-sim"
echo ""
echo " Verify:"
echo "   py scripts/aws/bookflow.py status"
echo "   aws ecs describe-services --cluster bookflow-ecs \\"
echo "     --services online-sim offline-sim \\"
echo "     --region ap-northeast-1 \\"
echo "     --query 'services[*].{name:serviceName,running:runningCount,status:status}'"
echo "================================================"
