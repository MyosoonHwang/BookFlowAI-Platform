# BOOKFLOW · task-rds-seed · Ansible 가 RDS 에 schema/seed 주입
#   대상: 영헌 (구축 phase 초기 1회 또는 매일 새 RDS 에)
#   전제: base-up.ps1 + task-data.ps1 (RDS 필요) + Ansible Node 부팅 완료
#   소요: ~3분 (Ansible playbook 실행)
#   비용: $0 (이미 떠있는 자원만 사용)
#
#   동작 흐름:
#     1. SSM Send-Command 로 Ansible Node 에 ansible-playbook 트리거
#     2. Ansible 이 Secrets Manager 에서 RDS password 읽음
#     3. psql 로 schema 생성 + 시드 데이터 INSERT

. (Join-Path $PSScriptRoot "..\_lib\deploy-stack.ps1")
. (Join-Path $PSScriptRoot "..\_lib\check-stack.ps1")

Write-Step "═══ task-rds-seed · Ansible playbook 실행 ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

# 의존성 체크
if (-not (Test-Stack -Name "rds" -Tier "20")) {
    Write-Err "RDS 미배포 · task-data.ps1 먼저 실행"; exit 1
}
if (-not (Test-Stack -Name "ansible-node" -Tier "30")) {
    Write-Err "Ansible Node 미배포 · base-up.ps1 먼저 실행"; exit 1
}

# Peering: Ansible CN → RDS (psql 접근)
Deploy-Stack -Tier "10" -Name "peering-ansible-data" -Template "10-network-core/peering/ansible-data.yaml"

# Ansible Node Instance ID 조회
$instanceId = aws cloudformation describe-stacks --stack-name "$env:BOOKFLOW_STACK_PREFIX-30-ansible-node" `
    --region $env:AWS_REGION `
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text

if (-not $instanceId) {
    Write-Err "Ansible Node Instance ID 조회 실패"; exit 1
}

Write-Info "Ansible Node: $instanceId"

# SSM Send-Command 로 Ansible playbook 트리거 (실제 playbook 은 추후 ansible/ 디렉토리에 작성)
Write-Info "ansible-playbook 트리거 (cicd/ansible/rds-seed.yml 추후 작성):"
Write-Info "  aws ssm send-command --instance-ids $instanceId ``"
Write-Info '    --document-name "AWS-RunShellScript" ``'
Write-Info '    --parameters ''commands=["cd /opt/bookflow && ansible-playbook cicd/ansible/rds-seed.yml"]'''

Write-Warn "Ansible playbook 디렉토리 (ansible/ or cicd/ansible/) 는 추후 작성 · 현재 placeholder"

Write-Step "═══ task-rds-seed 완료 (placeholder) ═══"
