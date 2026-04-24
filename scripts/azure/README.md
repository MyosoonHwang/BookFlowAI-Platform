# Azure 배포 스크립트 (민지 담당)

> Phase 2에 민지가 채울 placeholder.

## 참고

- AWS 버전 참고 모델: `scripts/aws/README.md`
- 실행 환경: Windows PowerShell (.ps1)
- Bicep 로컬 apply 방식 (`az deployment group create`)
- 자동화 파이프라인 없음 (개발 iteration 우선)

## 예상 구조 (민지가 확정)

```
scripts/azure/
├── config/
│   ├── azure.ps1
│   └── azure.local.ps1.example
├── _lib/
├── 0-initial/
├── 1-daily/
└── 2-tasks/
```

## 기본 사용 방식 (예상)

```powershell
# Bicep deploy 예시
az deployment group create `
  --resource-group bookflow-prod `
  --template-file infra/azure/99-content/logic-apps/main.bicep
```

AWS 측 값(Customer Gateway IP, TGW ID 등)은 영헌이 매일 단톡으로 공유하는 `exports/aws-YYYY-MM-DD.txt` 참고.
