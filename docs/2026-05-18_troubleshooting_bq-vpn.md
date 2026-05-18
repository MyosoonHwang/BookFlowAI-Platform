# 트러블슈팅 · BigQuery VPN 경유 전환 및 GCP 인증 해결

**날짜**: 2026-05-18  
**작업자**: 민지  
**상태**: ✅ 완료 (forecast_cache 80,000행 동기화 성공)

---

## 1. 배경 및 목표

| 항목 | 내용 |
|------|------|
| 목표 | EKS `forecast-svc` → BigQuery 호출 경로를 공인 인터넷에서 AWS↔GCP VPN 경유로 전환 |
| 이유 | 보안 정책상 GCP API 트래픽을 인터넷으로 내보내지 않고 전용 VPN 터널을 통해 PSC(Private Service Connect)로 라우팅 |
| 아키텍처 | EKS Pod → CoreDNS → PSC IP(10.50.0.10) → VPN 터널 → GCP all-apis PSC endpoint → BigQuery |

---

## 2. 문제 1 — BigQuery를 공인 인터넷으로 호출하는 코드 구조

### 원인

- `forecast.py`의 `_fetch_bigquery_forecast_rows()` 함수가 SA key JSON을 환경변수(`FORECAST_GCP_SA_KEY_JSON`)에서 직접 파싱하여 `google.oauth2.service_account.Credentials` 객체를 생성하고 BigQuery Client에 주입
- DNS가 `bigquery.googleapis.com` → 공인 IP로 해석 → 인터넷 경유 호출

### 해결

#### GCP 측: PSC + Cloud DNS (기존 구성 확인)

```
PSC endpoint:       10.50.0.10 (all-apis)
Cloud DNS zone:     *.googleapis.com → 10.50.0.10 (GCP VPC 내부 전용)
Cloud Router:       ALL_SUBNETS + 10.50.0.0/24 → AWS BGP 광고
```

#### GCP 측 추가: DNS inbound forwarding policy

```hcl
# BookFlowAI-Platform/infra/gcp/20-network-daily/psc.tf
resource "google_dns_policy" "inbound_forwarding" {
  name                      = "bookflow-dns-inbound"
  project                   = var.project_id
  enable_inbound_forwarding = true
  networks {
    network_url = data.google_compute_network.bookflow_vpc.id
  }
}
```

→ `terraform apply -target=google_dns_policy.inbound_forwarding` 적용 완료

#### EKS 측: CoreDNS 패치

```
# googleapis.com 쿼리를 PSC IP로 직접 반환 (VPN 경유)
googleapis.com:53 {
    template IN A googleapis.com {
        answer "{{ .Name }} 300 IN A 10.50.0.10"
    }
    template IN AAAA googleapis.com {
        rcode NOERROR
    }
}
```

→ `kubectl patch configmap coredns` + `kubectl rollout restart deployment coredns` 완료

#### 검증

```bash
# DNS 해석 확인
nslookup bigquery.googleapis.com
# → Address: 10.50.0.10  ✅

# TCP/SSL 연결 확인 (pod 내부)
socket.create_connection(('10.50.0.10', 443), timeout=5)  # → OK ✅
ssl wrap_socket bigquery.googleapis.com via 10.50.0.10     # → OK ✅
```

#### 코드 변경 (인터넷 호출 코드 제거)

| 파일 | 변경 내용 |
|------|-----------|
| `forecast.py` | `_fetch_bigquery_forecast_rows`: SA key 파싱 블록 제거 → ADC 사용 |
| `forecast.py` | `_call_vertex_sdk_direct`: credentials 주입 블록 제거 → ADC 사용 |
| `settings.py` | `gcp_sa_key_json` 필드 제거 |
| `deployment.yaml` | SA key volume mount + `GOOGLE_APPLICATION_CREDENTIALS=/var/run/gcp-sa/sa-key.json` 추가 |

---

## 3. 문제 2 — gcloud 권한 부족 및 SA key 발급 불가

### 원인

- `ms8405493@gmail.com` 계정은 `roles/editor`만 보유 → `resourcemanager.projects.setIamPolicy` 없음
- `iam.disableServiceAccountKeyCreation` org policy 적용 → 새 SA key 생성 불가 (`FAILED_PRECONDITION`)
- `bigquery.datasets.update` 없음 → BQ IAM 직접 수정 불가

### 해결: 기존 SA key 재사용

신규 SA 생성 대신 기존 AWS Secrets Manager 시크릿(`bookflow/glue/gcp-sa-key`)에 저장된 `bookflow-aws-connector` SA key를 재사용

```yaml
# externalsecret.yaml — 기존 시크릿 키 활용
- secretKey: FORECAST_GCP_SA_KEY_JSON
  remoteRef:
    key: bookflow/glue/gcp-sa-key   # bigquery.dataEditor + jobUser 권한 보유
```

```yaml
# deployment.yaml — 파일 마운트로 ADC 설정
volumes:
  - name: gcp-sa-key
    secret:
      secretName: forecast-svc-secret
      items:
        - key: FORECAST_GCP_SA_KEY_JSON
          path: sa-key.json
containers:
  - env:
      - name: GOOGLE_APPLICATION_CREDENTIALS
        value: /var/run/gcp-sa/sa-key.json
```

### ADC(Application Default Credentials) 흐름

```
Pod 기동 → GOOGLE_APPLICATION_CREDENTIALS 환경변수 탐지
→ /var/run/gcp-sa/sa-key.json 로드
→ BigQuery/Vertex AI SDK가 자동으로 해당 SA로 인증
→ bigquery.googleapis.com 해석 → 10.50.0.10 (PSC) → VPN → GCP
```

---

## 4. 문제 3 — gcloud ADC 토큰 발급 실패

### 원인

- Terraform apply 시 `GOOGLE_APPLICATION_CREDENTIALS` 미설정 → ADC 없음
- `gcloud auth application-default login` 브라우저 인증 중 `cloud-platform` 스코프 미동의

### 해결

별도 PowerShell 창에서 직접 실행 후 브라우저에서 **모든 스코프 허용** 체크:

```powershell
& "C:\Users\campus3S027\AppData\Local\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd" auth application-default login
```

→ `~/.config/gcloud/application_default_credentials.json` 생성 완료  
→ Terraform provider 인증 정상화

---

## 5. 최종 결과

### forecast_cache 동기화 성공

```
POST /forecast/refresh
status=200
body={"inserted":80000,"source":"bigquery"}

snapshot_date | count
2026-05-16    | 16,000
2026-05-17    | 16,000
2026-05-18    | 16,000
2026-05-19    | 16,000
2026-05-20    | 16,000
```

### 트래픽 경로 확인

```
bigquery.googleapis.com → 10.50.0.10 (PSC via VPN)  ✅
TCP 10.50.0.10:443                                    ✅
SSL handshake                                          ✅
BigQuery 쿼리 완료 (80,000행, ~200초)                 ✅
RDS forecast_cache upsert                             ✅
```

### 배포 완료 목록

| 항목 | 내용 |
|------|------|
| GCP | `google_dns_policy.inbound_forwarding` terraform apply |
| EKS | CoreDNS ConfigMap 패치 + rollout restart |
| EKS | `forecast-svc` deployment.yaml volume mount 추가 |
| EKS | `forecast-svc` rollout restart (새 deployment spec 반영) |
| 코드 | `forecast.py` 인터넷 경유 인증 코드 제거 |
| 코드 | `settings.py` `gcp_sa_key_json` 필드 제거 |
| 자동화 | CronJob `forecast-bq-refresh` 매일 22:00 UTC(07:00 KST) 실행 예정 |

---

## 6. 남은 작업 (대시보드 표시 위해 필요)

> RDS 운영 기반 시드 데이터가 없어서 대시보드 metric이 모두 0으로 표시됨

| 순서 | 작업 | 명령 |
|------|------|------|
| 1 | seed CSV 생성 | `py infra/aws/20-data-persistent/seed-data/generate.py` |
| 2 | RDS seed 재실행 | `python bookflow.py task rds-seed` 또는 `scripts/aws/ops/seed.sh up` |
| 3 | plan-daily 재실행 | `POST /dashboard/cascade/plan-daily` |
| 4 | 대시보드 확인 | `pending_orders`, `insufficient-stock`, metric card 표시 |
