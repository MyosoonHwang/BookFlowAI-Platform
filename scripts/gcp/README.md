# GCP 배포 스크립트 (우혁 담당)

> Phase 2에 우혁이 채울 placeholder.

## 참고

- AWS 버전 참고 모델: `scripts/aws/README.md`
- 실행 환경: Windows PowerShell (.ps1)
- Terraform 로컬 apply 방식 (`terraform apply`)
- State는 GCS backend로 공유
- 자동화 파이프라인 없음 (개발 iteration 우선)

## 예상 구조 (우혁이 확정)

```
scripts/gcp/
├── config/
│   ├── gcp.ps1
│   └── gcp.local.ps1.example
├── _lib/
├── 0-initial/
├── 1-daily/
└── 2-tasks/
```

## 기본 사용 방식 (예상)

```powershell
# Terraform apply 예시
cd infra/gcp/99-content
terraform init -backend-config="bucket=bookflow-tf-state"
terraform apply -auto-approve
```

AWS 측 값(Customer Gateway IP, TGW ID 등)은 영헌이 매일 단톡으로 공유하는 `exports/aws-YYYY-MM-DD.txt` 참고.
