# lambdas

V6.3 / V6.2 Tier 99-serverless · 7 Lambdas (cron + Kinesis ESM + API GW).

## 현재 상태 (Phase 3)
- **`pos-ingestor`** — Kinesis ESM consumer · sales_realtime/inventory/audit_log + Redis pub stock.changed (real)
- 나머지 6 Lambda — `infra/aws/99-serverless/sam-template.yaml` InlineCode placeholder (코드 후속)

## 빌드 + 배포 (CodeStar 부재 임시 우회)
```bash
# 1. zip + S3 upload
AWS_PROFILE=bookflow-admin AWS_REGION=ap-northeast-1 ./build.sh pos-ingestor

# 2. SAM template 의 CodeUri 가 s3://bookflow-cp-artifacts-${ACCOUNT}/lambda/pos-ingestor.zip 가리킴
# 3. CFN deploy (Platform aws · sam-cli or aws cloudformation)
cd ../../BookFlowAI-Platform/infra/aws/99-serverless
aws cloudformation deploy --profile bookflow-admin --region ap-northeast-1 \
    --template-file sam-template.yaml \
    --stack-name bookflow-99-serverless \
    --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND
```

## 평일 CodeStar 복구 시
- CodePipeline 가 `main` push 감지 → CodeBuild → S3 zip → CFN update
- `lambdas/buildspec.yml` 추가 후 cicd-eks 와 동일 패턴

## 환경변수 (per Lambda)
- pos-ingestor: `RDS_HOST` `RDS_USER=pos_ingestor` `RDS_SECRET_ARN` `REDIS_HOST` (VPC 내부)
