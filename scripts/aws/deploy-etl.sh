#!/usr/bin/env bash
# deploy-etl.sh - BookFlow ETL full pipeline deploy
# Order: ECR image build/push -> SAM Lambda deploy -> Glue scripts S3 sync
# Prerequisites: AWS CLI configured, Docker running, SAM CLI installed
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-1}"
PROJECT="bookflow"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Get AWS account info
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
GLUE_BUCKET="${PROJECT}-glue-scripts-${ACCOUNT_ID}"
RAW_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name "${PROJECT}-00-s3" \
  --query "Stacks[0].Outputs[?OutputKey=='RawBucketName'].OutputValue" \
  --output text 2>/dev/null || echo "${PROJECT}-raw-${ACCOUNT_ID}")

echo "============================================"
echo " BookFlow ETL Deploy"
echo " Account : ${ACCOUNT_ID}"
echo " Region  : ${REGION}"
echo " ECR     : ${ECR_REGISTRY}"
echo " Glue S3 : s3://${GLUE_BUCKET}/scripts/"
echo "============================================"

# 1. ECR login
echo ""
echo "[1/5] ECR login..."
aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# 2. ECS simulator image build & push
echo ""
echo "[2/5] ECS simulator image build..."

for SIM in online-sim offline-sim; do
  SIM_DIR="${REPO_ROOT}/ecs-sims/${SIM}"
  IMAGE="${ECR_REGISTRY}/${PROJECT}/${SIM}:latest"

  echo "  -> ${SIM} build..."
  docker build -t "${IMAGE}" "${SIM_DIR}"
  docker push "${IMAGE}"
  echo "  OK ${IMAGE} pushed"
done

# 3. ECS service rolling update
echo ""
echo "[3/5] ECS service rolling update..."

ECS_CLUSTER=$(aws cloudformation describe-stacks \
  --stack-name "${PROJECT}-30-ecs-cluster" \
  --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" \
  --output text 2>/dev/null || echo "${PROJECT}-ecs")

for SIM in online-sim offline-sim; do
  echo "  -> ${SIM} force-new-deployment..."
  aws ecs update-service \
    --cluster "${ECS_CLUSTER}" \
    --service "${SIM}" \
    --force-new-deployment \
    --region "${REGION}" \
    --output json | python3 -c "
import sys, json
s = json.load(sys.stdin)['service']
print(f\"  OK {s['serviceName']} -> {s['desiredCount']} tasks\")
" || echo "  WARN ${SIM} service update failed (service may not be deployed yet)"
done

# 4. Lambda SAM deploy
echo ""
echo "[4/5] Lambda SAM deploy..."

LAMBDA_DIR="${REPO_ROOT}/infra/aws/99-serverless"
SAM_TEMPLATE="${LAMBDA_DIR}/sam-template.yaml"

# Get Step Functions ARN (if glue stack is deployed)
SF_ARN=$(aws cloudformation describe-stacks \
  --stack-name "${PROJECT}-99-step-functions" \
  --query "Stacks[0].Outputs[?OutputKey=='Etl3StateMachineArn'].OutputValue" \
  --output text 2>/dev/null || echo "")

cd "${LAMBDA_DIR}"

SAM_PARAMS="ParameterKey=ProjectName,ParameterValue=${PROJECT}"
if [ -n "${SF_ARN}" ]; then
  SAM_PARAMS="${SAM_PARAMS} ParameterKey=StepFunctionsArn,ParameterValue=${SF_ARN}"
  echo "  Step Functions ARN: ${SF_ARN}"
fi

sam deploy \
  --template-file "${SAM_TEMPLATE}" \
  --stack-name "${PROJECT}-99-lambdas" \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND CAPABILITY_IAM \
  --region "${REGION}" \
  --parameter-overrides ${SAM_PARAMS} \
  --no-fail-on-empty-changeset

echo "  OK Lambda deploy complete"

# 5. Glue scripts S3 sync
echo ""
echo "[5/5] Glue scripts S3 sync..."

GLUE_JOBS_DIR="${REPO_ROOT}/glue-jobs"
aws s3 sync "${GLUE_JOBS_DIR}/" "s3://${GLUE_BUCKET}/scripts/" \
  --region "${REGION}" \
  --exclude "*.pyc" \
  --exclude "__pycache__/*"

echo "  OK Glue scripts synced"

echo ""
echo "============================================"
echo " ETL Deploy Complete"
echo " ECS sims  : online-sim / offline-sim"
echo " Lambdas   : 7 (aladin-sync / event-sync / sns-gen"
echo "             spike-detect / forecast-trigger"
echo "             secret-forwarder / pos-ingestor)"
echo " Glue      : s3://${GLUE_BUCKET}/scripts/"
echo "             (6 jobs: raw_pos/sns/aladin/event / sales_daily / features)"
echo ""
echo " Next steps:"
echo "   1. Check ECS tasks: aws ecs list-tasks --cluster ${ECS_CLUSTER}"
echo "   2. Test Lambda: aws lambda invoke --function-name ${PROJECT}-aladin-sync /dev/null"
echo "   3. Run Glue job: aws glue start-job-run --job-name ${PROJECT}-raw-pos-mart"
echo "   4. Check CloudWatch Logs: /aws/lambda/${PROJECT}-* / /aws-glue/jobs/"
echo "============================================"
