# BOOKFLOW · task-full-stack · 모든 task 한방에 실행 (통합 시연용)
#   대상: 시연·통합 테스트 (3명 동시 작업)
#   전제: base-up.ps1 완료
#   소요: ~30분 (병렬 불가 · 순차 deploy)
#   비용: ~$5.60/일 (data + msa-pods + etl-streaming + publisher 합계)
#
#   순서:
#     1. task-data       (RDS · Redis · Kinesis)
#     2. task-msa-pods   (EKS Cluster + Node Group + endpoints-bookflow-ai)
#     3. task-etl-streaming (ECS sims + endpoints-sales-data)
#     4. task-publisher  (Publisher ASG + ECS inventory-api)
#
#   제외:
#     task-auth-pod / task-forecast (Tier 60 VPN · Phase 2-3 활성)
#     task-rds-seed (Ansible playbook · data 후 별도 실행)

. (Join-Path $PSScriptRoot "..\_lib\common.ps1")

Write-Step "═══ task-full-stack · 통합 시연 deploy ═══"

$start = Get-Date

& (Join-Path $PSScriptRoot "task-data.ps1")
if ($LASTEXITCODE -ne 0) { Write-Err "task-data 실패"; exit 1 }

& (Join-Path $PSScriptRoot "task-msa-pods.ps1")
if ($LASTEXITCODE -ne 0) { Write-Err "task-msa-pods 실패"; exit 1 }

& (Join-Path $PSScriptRoot "task-etl-streaming.ps1")
if ($LASTEXITCODE -ne 0) { Write-Err "task-etl-streaming 실패"; exit 1 }

& (Join-Path $PSScriptRoot "task-publisher.ps1")
if ($LASTEXITCODE -ne 0) { Write-Err "task-publisher 실패"; exit 1 }

$elapsed = (Get-Date) - $start
Write-Step ("═══ task-full-stack 완료 · 소요 {0:mm\:ss} ═══" -f $elapsed)
Write-Info  "추가 옵션:"
Write-Info  "  task-rds-seed.ps1   (Ansible 시드 주입)"
Write-Info  "  task-auth-pod.ps1   (Azure VPN · Phase 2)"
Write-Info  "  task-forecast.ps1   (GCP VPN · Phase 2)"
