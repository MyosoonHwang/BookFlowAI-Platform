# BOOKFLOW · task-rds-seed-down · Ansible playbook 자체 자원 없음 · peering-ansible-data 만 destroy
#   주의: RDS 데이터는 별도 (task-data-down 에서 RDS destroy 시 데이터 사라짐)
#   Ansible Node 자체는 base-up 자원 (base-down 으로만 destroy)

. (Join-Path $PSScriptRoot "..\_lib\destroy-stack.ps1")

Write-Step "═══ task-rds-seed-down · peering-ansible-data destroy ═══"

if (-not (Test-AwsCredentials)) { Write-Err "AWS 인증 실패"; exit 1 }

Remove-StackSafe -Tier "10" -Name "peering-ansible-data"

Write-Step "═══ task-rds-seed-down 완료 ═══"
