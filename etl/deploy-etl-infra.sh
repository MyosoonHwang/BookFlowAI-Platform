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

echo "================================================"
echo " BookFlow ETL Infrastructure Deploy"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================"

# Step 0: ensure S3 stack has Outputs (deploy without import if already managed)
echo ""
echo "[0/3] S3 stack (bookflow-00-s3)..."
S3_STATUS=$(aws cloudformation describe-stacks \
  --stack-name "${PROJECT}-00-s3" \
  --query "Stacks[0].StackStatus" \
  --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "${S3_STATUS}" = "DOES_NOT_EXIST" ] || [ "${S3_STATUS}" = "REVIEW_IN_PROGRESS" ]; then
  echo "  WARNING: ${PROJECT}-00-s3 stack not in UPDATE_COMPLETE state (status: ${S3_STATUS})"
  echo "  Run import-s3-buckets.sh first to import existing S3 buckets."
  echo "  Continuing - downstream stacks that ImportValue s3 exports may fail."
else
  echo "  OK ${PROJECT}-00-s3 is ${S3_STATUS}"
fi

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

# Step 3: task-etl-streaming (endpoints + ECS sims)
echo ""
echo "[3/3] task-etl-streaming (VPC endpoints + ECS online/offline-sim)..."
${SCRIPT} task etl-streaming
echo "  OK task-etl-streaming complete"

echo ""
echo "================================================"
echo " Deploy Complete"
echo " - Tier 10: vpc-sales-data / vpc-egress / vpc-data / vpc-bookflow-ai"
echo " -          endpoints-sales-data (ECR/Kinesis/CWLogs/S3)"
echo " - Tier 20: RDS / Redis / Kinesis"
echo " - Tier 30: ECS cluster (bookflow-ecs)"
echo " - Tier 40: ECS online-sim / offline-sim"
echo ""
echo " Verify:"
echo "   py scripts/aws/bookflow.py status"
echo "   aws ecs describe-services --cluster bookflow-ecs \\"
echo "     --services online-sim offline-sim \\"
echo "     --region ap-northeast-1 \\"
echo "     --query 'services[*].{name:serviceName,running:runningCount,status:status}'"
echo "================================================"
