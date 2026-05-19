"""Row 9 — 장애 시나리오·복원력 대시보드.

출처: Notion "시나리오 검증 작업 가이드" (365b4343-5916-801f-b98d-ecd7e5b1fd82).
장애 시나리오 8개가 전부 CLI(kubectl/aws/gcloud/az)로만 검증 가능하던 것을
Grafana 에서 눈으로 보게 만든다. 발표 데모용으로도 활용.

de-dup 원칙: Row 1/3/6/8 과 메트릭이 겹치나 — 이 대시보드는 **시나리오/드릴
검증 관점** (장애 발생→복구를 한 화면에서 추적) vs Row 1~8 = 정상상태 모니터링.
목적이 달라 별도 대시보드로 정당하다.

시나리오 8개 = 각각 패널 1묶음:
  ① 현재 상태 신호등 stat (정상/장애)  ② 발생→복구 타임라인  ③ 트리거 명령 text

시나리오 매핑:
  1. EKS Pod 장애          Prometheus up{namespace="bookflow"} · 컨테이너 재시작
  2. 노드 오토스케일링      Prometheus up{job="kubernetes-nodes"} count
  3. RDS Failover          CloudWatch AWS/RDS DatabaseConnections·CPU
  4. Publisher ASG         CloudWatch AWS/AutoScaling (SEARCH · CodeDeploy ASG)
  5. GCP Cloud Function    GCP cloudfunctions execution_count (status 별)
  6. GCP VPN 터널          CloudWatch AWS/VPN TunnelState
  7. Azure Logic Apps      Azure Monitor AzureDiagnostics(MICROSOFT.LOGIC)
  8. Client VPN            CloudWatch AWS/ClientVPN ActiveConnectionsCount

라이브 검증 (2026-05-19 · admin 994878981869 · Grafana datasource proxy):
  ✅ S1 up{namespace="bookflow"} 7 pod · changes(container_start_time) 21 series
  ✅ S2 up{job="kubernetes-nodes"}==1 = 2 노드
  ✅ S3 AWS/RDS DatabaseConnections 72 pts
  ✅ S6 AWS/VPN TunnelState 72 pts
  ✅ S7 AzureDiagnostics MICROSOFT.LOGIC 10 rows
  ⚠️ S4 Publisher CodeDeploy ASG 미배포(데일리 자원) → SEARCH 식 · placeholder
  ⚠️ S5 admin 클러스터 GCP oauth egress 차단 → 쿼리형태 row3 검증분과 동일 · placeholder
  ⚠️ S8 admin 계정 Client VPN endpoint 메트릭 미발행 → placeholder

새 Row 모듈 패턴(README §"새 Row 추가 패턴")을 따른다.
"""

from grafana_foundation_sdk.builders.cloudwatch import (
    CloudWatchMetricsQuery as CWMetrics,
)
from grafana_foundation_sdk.builders.dashboard import Dashboard, Row
from grafana_foundation_sdk.builders.prometheus import Dataquery as PromQuery
from grafana_foundation_sdk.builders.azuremonitor import (
    AzureLogsQuery,
    AzureMonitorQuery,
)
from grafana_foundation_sdk.builders.googlecloudmonitoring import (
    CloudMonitoringQuery,
    TimeSeriesList,
)
from grafana_foundation_sdk.builders.text import Panel as TextPanel
from grafana_foundation_sdk.models.azuremonitor import ResultFormat
from grafana_foundation_sdk.models.cloudwatch import (
    CloudWatchQueryMode,
    MetricEditorMode,
    MetricQueryType,
)
from grafana_foundation_sdk.models.common import BigValueGraphMode
from grafana_foundation_sdk.models.dashboard import (
    DashboardSpecialValueMapOptions,
    SpecialValueMap,
    SpecialValueMatch,
    ValueMap,
    ValueMappingResult,
)
from grafana_foundation_sdk.models.text import TextMode

from lib import datasources as ds
from lib import panels as pb
from lib.meta import base_dashboard

UID = "bookflow-ops-row9-resilience"
TITLE = "BookFlow 운영 — 장애 시나리오·복원력"
DESCRIPTION = (
    "장애 시나리오 8개의 발생→복구를 한 화면에서 검증한다. 각 시나리오 = "
    "현재 상태 신호등 + 발생/복구 타임라인 + 트리거 명령. EKS Pod·노드 오토스케일링·"
    "RDS Failover·Publisher ASG·GCP Cloud Function·GCP VPN 터널·Azure Logic Apps·"
    "Client VPN. 시나리오/드릴 검증 관점 — 정상상태 모니터링은 Row 1~8."
)

# ── 라이브 좌표 ──────────────────────────────────────────────────────────
AWS_REGION = "ap-northeast-1"
RDS_ID = "bookflow-postgres"
# Publisher CodeDeploy ASG — 데일리 자원·blue/green 배포마다 식별자 회전.
# Notion 가이드 기준 식별자. 미배포 시 SEARCH 식이 빈 결과(placeholder).
PUBLISHER_ASG = "CodeDeploy_bookflow-publisher-bg_d-TOW7F0I5J"
# cross-cloud S2S VPN — AWS↔GCP (Row 6 와 동일 실측 ID)
VPN_AWS_GCP = "vpn-0acce17f17cf493e7"
# Azure Log Analytics 워크스페이스 (Logic Apps WorkflowRuntime 진단 로그)
SUBSCRIPTION = "e98a94bb-7532-4e49-8a36-bc42e30d5a81"
RESOURCE_GROUP = "rg-bookflow"
LAW_RESOURCE_ID = (
    f"/subscriptions/{SUBSCRIPTION}/resourceGroups/{RESOURCE_GROUP}"
    f"/providers/Microsoft.OperationalInsights/workspaces/law-bookflowmj"
)
GCP_PROJECT = "project-8ab6bf05-54d2-4f5d-b8d"

BOOKFLOW_NS = 'namespace="bookflow"'


# ── value mappings ──────────────────────────────────────────────────────
# UP/DOWN — 1=정상 / 0=장애
_UPDOWN_MAP = ValueMap(
    options={
        "0": ValueMappingResult(text="DOWN", color=pb.RED),
        "1": ValueMappingResult(text="UP", color=pb.GREEN),
    }
)
_NODATA_MAP = SpecialValueMap(
    options=DashboardSpecialValueMapOptions(
        match=SpecialValueMatch.NULL,
        result=ValueMappingResult(text="N/A", color=pb.YELLOW),
    )
)


# ── datasource ref 헬퍼 (패널 + 쿼리 공용) ──────────────────────────────
def _prom():
    return ds.ref(ds.PROMETHEUS)


def _cw():
    return ds.ref(ds.CLOUDWATCH)


def _azure():
    return ds.ref(ds.AZURE_MONITOR)


def _gcp():
    return ds.ref(ds.GCP_MONITORING)


# ── 쿼리 빌더 헬퍼 — 패널·쿼리 양쪽에 datasource 명시 (no-data 회피) ────
def _prom_q(expr: str, ref_id: str = "A", *, instant: bool = False, legend: str = ""):
    q = PromQuery().datasource(_prom()).expr(expr).ref_id(ref_id)
    if instant:
        q = q.instant()
    else:
        q = q.range()
    if legend:
        q = q.legend_format(legend)
    return q


def _cw_metric(ref_id, namespace, metric, dims, *, stat="Average",
               period="300", label="", match_exact=True):
    return (
        CWMetrics()
        .datasource(_cw())
        .query_mode(CloudWatchQueryMode.METRICS)
        .metric_query_type(MetricQueryType.SEARCH)
        .metric_editor_mode(MetricEditorMode.BUILDER)
        .region(AWS_REGION)
        .namespace(namespace)
        .metric_name(metric)
        .dimensions(dims)
        .statistic(stat)
        .period(period)
        .match_exact(match_exact)
        .label(label)
        .ref_id(ref_id)
    )


def _cw_search(ref_id, namespace, expression, *, stat="Average",
               period="300", label=""):
    """SEARCH 식 CloudWatch 쿼리 — dimension 값(식별자)이 회전해도 자동 대응."""
    return (
        CWMetrics()
        .datasource(_cw())
        .query_mode(CloudWatchQueryMode.METRICS)
        .metric_query_type(MetricQueryType.SEARCH)
        .metric_editor_mode(MetricEditorMode.BUILDER)
        .region(AWS_REGION)
        .namespace(namespace)
        .expression(expression)
        .statistic(stat)
        .period(period)
        .label(label)
        .ref_id(ref_id)
    )


def _azure_logs(kql: str, result_format: ResultFormat) -> AzureMonitorQuery:
    logs = (
        AzureLogsQuery()
        .query(kql)
        .resources([LAW_RESOURCE_ID])
        .result_format(result_format)
        .dashboard_time(True)
    )
    return (
        AzureMonitorQuery()
        .query_type("Azure Log Analytics")
        .subscription(SUBSCRIPTION)
        .azure_log_analytics(logs)
        .datasource(_azure())
    )


def _gcp_ts(metric_type: str, *, aligner="ALIGN_SUM", reducer="REDUCE_SUM",
            group_bys=None, extra_filters=None, alias="",
            alignment_period="+300s") -> CloudMonitoringQuery:
    filters = [f'metric.type="{metric_type}"']
    if extra_filters:
        filters.extend(extra_filters)
    tsl = (
        TimeSeriesList()
        .project_name(GCP_PROJECT)
        .filters(filters)
        .per_series_aligner(aligner)
        .cross_series_reducer(reducer)
        .alignment_period(alignment_period)
    )
    if group_bys:
        tsl = tsl.group_bys(group_bys)
    q = (
        CloudMonitoringQuery()
        .query_type("timeSeriesList")
        .time_series_list(tsl)
        .datasource(_gcp())
    )
    if alias:
        q = q.alias_by(alias)
    return q


def _trigger_text(title: str, body: str) -> TextPanel:
    """시나리오 트리거 명령 안내 text 패널 (markdown)."""
    return (
        TextPanel()
        .title(title)
        .span(pb.SPAN_QUARTER)
        .height(pb.HEIGHT_STAT)
        .mode(TextMode.MARKDOWN)
        .content(body)
    )


# ════════════════════════════════════════════════════════════════════════
# 시나리오 1 — EKS Pod 장애
# ════════════════════════════════════════════════════════════════════════
def _s1_pod_health():
    """현재 상태 — bookflow 네임스페이스 정상 Pod 수."""
    p = pb.stat_panel(
        "① 현재 상태 · 정상 Pod 수",
        unit="short",
        color_mode=pb.BigValueColorMode.VALUE,
        thresholds=pb._thresholds([(None, pb.RED), (1, pb.YELLOW), (7, pb.GREEN)]),
        mappings=[_NODATA_MAP],
        description="Prometheus up{namespace=\"bookflow\"}==1 합계. 설계 7 Pod.",
    )
    return p.datasource(_prom()).with_target(
        _prom_q(f'sum(up{{{BOOKFLOW_NS}}} == 1)', instant=True, legend="정상 Pod")
    )


def _s1_pod_timeline():
    """발생→복구 — Pod 별 up(1/0) 타임라인. 죽음→복구가 그래프로."""
    p = pb.timeseries_panel(
        "② 발생→복구 · Pod 별 가동 상태",
        unit="short",
        span=pb.SPAN_HALF,
        description=(
            "Prometheus up{namespace=\"bookflow\"} — Pod 별 1=Up/0=Down. "
            "kubectl delete pod 시 해당 시리즈 0→1 복구가 보인다."
        ),
    )
    return p.datasource(_prom()).with_target(
        _prom_q(f'up{{{BOOKFLOW_NS}}}', legend="{{pod}}")
    )


def _s1_pod_restarts():
    """발생→복구 — 컨테이너 재시작 감지 (replacement Pod 가동 신호).

    kube-state-metrics 미설치(라이브 실측) → kube_pod_*_restarts 부재.
    cAdvisor container_start_time_seconds 의 1h 내 변화로 재시작을 감지한다.
    """
    p = pb.timeseries_panel(
        "② 컨테이너 재시작 감지",
        unit="short",
        span=pb.SPAN_QUARTER,
        fill_opacity=30,
        description=(
            "changes(container_start_time_seconds{namespace=\"bookflow\"}[1h]) — "
            "kube-state-metrics 미설치 → cAdvisor 시작시각 변화로 재시작 감지."
        ),
    )
    return p.datasource(_prom()).with_target(
        _prom_q(
            f'changes(container_start_time_seconds{{{BOOKFLOW_NS},pod!=""}}[1h])',
            legend="{{pod}}",
        )
    )


def _s1_trigger():
    return _trigger_text(
        "③ 트리거 — EKS Pod 장애",
        "**Pod 강제 장애**\n```\nkubectl delete pod -n bookflow <pod>\n```\n"
        "**기대**: Terminating → 신규 Pod Running · 5xx 0건(무중단).",
    )


# ════════════════════════════════════════════════════════════════════════
# 시나리오 2 — 노드 오토스케일링
# ════════════════════════════════════════════════════════════════════════
def _s2_node_count():
    """현재 상태 — Ready 노드 수."""
    p = pb.stat_panel(
        "① 현재 상태 · Ready 노드 수",
        unit="short",
        color_mode=pb.BigValueColorMode.VALUE,
        thresholds=pb._thresholds([(None, pb.RED), (1, pb.YELLOW), (2, pb.GREEN)]),
        mappings=[_NODATA_MAP],
        description="Prometheus count(up{job=\"kubernetes-nodes\"}==1).",
    )
    return p.datasource(_prom()).with_target(
        _prom_q('count(up{job="kubernetes-nodes"} == 1)',
                instant=True, legend="Ready 노드")
    )


def _s2_node_timeline():
    """발생→복구 — 노드 수 추세. scale-up 이 그래프로."""
    p = pb.timeseries_panel(
        "② 발생→복구 · 노드 수 추세 (scale-up)",
        unit="short",
        span=pb.SPAN_HALF,
        fill_opacity=20,
        description=(
            "count(up{job=\"kubernetes-nodes\"}==1) 추세. node drain 후 "
            "Cluster Autoscaler 가 신규 노드를 띄우면 계단형 증가가 보인다."
        ),
    )
    return p.datasource(_prom()).with_target(
        _prom_q('count(up{job="kubernetes-nodes"} == 1)', legend="Ready 노드")
    )


def _s2_pod_distribution():
    """발생→복구 — 노드별 Pod 분포. drain 후 재배치가 보인다."""
    p = pb.timeseries_panel(
        "② 노드별 Pod 분포 (재배치)",
        unit="short",
        span=pb.SPAN_QUARTER,
        description=(
            "노드별 실행 컨테이너 수 (cAdvisor). node drain 시 한 노드가 "
            "0 으로 떨어지고 다른 노드로 Pod 가 재배치되는 게 보인다."
        ),
    )
    return p.datasource(_prom()).with_target(
        _prom_q(
            f'count(container_start_time_seconds{{{BOOKFLOW_NS},pod!=""}}) by (instance)',
            legend="{{instance}}",
        )
    )


def _s2_trigger():
    return _trigger_text(
        "③ 트리거 — 노드 오토스케일링",
        "**노드 강제 drain**\n```\nkubectl drain <node> \\\n"
        "  --ignore-daemonsets --delete-emptydir-data\n```\n"
        "**기대**: Pod 정상 노드 재배치 · 신규 노드 Ready · CA scale-up.",
    )


# ════════════════════════════════════════════════════════════════════════
# 시나리오 3 — RDS Failover
# ════════════════════════════════════════════════════════════════════════
def _s3_rds_connections():
    """현재 상태 — RDS DB 연결 수 (0 이면 단절)."""
    p = pb.stat_panel(
        "① 현재 상태 · RDS 연결 수",
        unit="short",
        color_mode=pb.BigValueColorMode.VALUE,
        thresholds=pb._thresholds([(None, pb.RED), (1, pb.GREEN)]),
        mappings=[_NODATA_MAP],
        description="AWS/RDS DatabaseConnections — bookflow-postgres. 0=단절.",
    )
    return p.datasource(_cw()).with_target(
        _cw_metric("A", "AWS/RDS", "DatabaseConnections",
                   {"DBInstanceIdentifier": RDS_ID}, stat="Average", label="연결")
    )


def _s3_rds_timeline():
    """발생→복구 — 연결·CPU 타임라인. failover 순간 blip→복구."""
    p = pb.timeseries_panel(
        "② 발생→복구 · RDS 연결 / CPU (failover blip)",
        unit="short",
        span=pb.SPAN_HALF,
        description=(
            "AWS/RDS DatabaseConnections·CPUUtilization. failover-db-cluster "
            "트리거 시 연결 순간 단절(30초~2분)→재연결이 보인다."
        ),
    )
    return (
        p.datasource(_cw())
        .with_target(_cw_metric("A", "AWS/RDS", "DatabaseConnections",
                                {"DBInstanceIdentifier": RDS_ID},
                                stat="Average", label="연결 수"))
        .with_target(_cw_metric("B", "AWS/RDS", "CPUUtilization",
                                {"DBInstanceIdentifier": RDS_ID},
                                stat="Average", label="CPU %"))
    )


def _s3_rds_writeio():
    """발생→복구 — write IOPS. failover 후 write 재개 신호."""
    p = pb.timeseries_panel(
        "② RDS Write IOPS",
        unit="iops",
        span=pb.SPAN_QUARTER,
        description="AWS/RDS WriteIOPS — failover 후 write 트래픽 재개 신호.",
    )
    return p.datasource(_cw()).with_target(
        _cw_metric("A", "AWS/RDS", "WriteIOPS",
                   {"DBInstanceIdentifier": RDS_ID}, stat="Average", label="Write")
    )


def _s3_trigger():
    return _trigger_text(
        "③ 트리거 — RDS Failover",
        "**Failover 강제 트리거**\n```\naws rds failover-db-cluster \\\n"
        "  --db-cluster-identifier bookflow-rds \\\n"
        "  --region ap-northeast-1\n```\n"
        "**기대**: Multi-AZ failover 완료 · 30초~2분 내 복구.",
    )


# ════════════════════════════════════════════════════════════════════════
# 시나리오 4 — Publisher ASG (EC2 오토스케일링)
# ════════════════════════════════════════════════════════════════════════
def _s4_asg_capacity():
    """현재 상태 — Publisher ASG InService 인스턴스 수.

    SEARCH 식 사용 — Publisher CodeDeploy ASG 식별자는 blue/green 배포마다
    회전한다. 데일리 자원이라 미배포 시 결과 없음(placeholder).
    """
    p = pb.stat_panel(
        "① 현재 상태 · Publisher InService",
        unit="short",
        color_mode=pb.BigValueColorMode.VALUE,
        thresholds=pb._thresholds([(None, pb.RED), (2, pb.GREEN)]),
        mappings=[_NODATA_MAP],
        description=(
            "AWS/AutoScaling GroupInServiceInstances · publisher ASG SEARCH. "
            "Min2/Max4. 데일리 CodeDeploy ASG 미배포 시 N/A(placeholder)."
        ),
    )
    return p.datasource(_cw()).with_target(
        _cw_search(
            "A", "AWS/AutoScaling",
            "SEARCH('{AWS/AutoScaling,AutoScalingGroupName} "
            "AutoScalingGroupName=\"CodeDeploy_bookflow-publisher\" "
            "MetricName=\"GroupInServiceInstances\"', 'Average', 300)",
            stat="Average", label="InService",
        )
    )


def _s4_asg_timeline():
    """발생→복구 — Desired vs InService 타임라인. 2→3 스케일아웃.

    placeholder: Publisher CodeDeploy ASG(CodeDeploy_bookflow-publisher-bg_*)
    는 데일리 자원 — 라이브 admin 계정에 현재 미배포(EKS 노드 ASG 만 존재).
    publisher 배포 + CPU TargetTracking 정책 트리거 시 본 패널이 동작한다.
    """
    p = pb.timeseries_panel(
        "② 발생→복구 · ASG Desired / InService (2→3 스케일아웃)",
        unit="short",
        span=pb.SPAN_HALF,
        description=(
            "AWS/AutoScaling GroupDesiredCapacity·GroupInServiceInstances · "
            "publisher ASG SEARCH. CPU 0.3% TargetTracking 트리거 시 2→3. "
            "placeholder — CodeDeploy ASG 데일리 자원·현재 미배포."
        ),
    )
    return (
        p.datasource(_cw())
        .with_target(_cw_search(
            "A", "AWS/AutoScaling",
            "SEARCH('{AWS/AutoScaling,AutoScalingGroupName} "
            "AutoScalingGroupName=\"CodeDeploy_bookflow-publisher\" "
            "MetricName=\"GroupDesiredCapacity\"', 'Average', 300)",
            stat="Average", label="Desired"))
        .with_target(_cw_search(
            "B", "AWS/AutoScaling",
            "SEARCH('{AWS/AutoScaling,AutoScalingGroupName} "
            "AutoScalingGroupName=\"CodeDeploy_bookflow-publisher\" "
            "MetricName=\"GroupInServiceInstances\"', 'Average', 300)",
            stat="Average", label="InService"))
    )


def _s4_trigger():
    return _trigger_text(
        "③ 트리거 — Publisher ASG",
        "**TargetTracking CPU 0.3% 정책 → 스케일아웃**\n```\n"
        "python publisher_asg_test.py test\n```\n"
        f"대상 ASG `{PUBLISHER_ASG}`\n"
        "**기대**: Desired 2 → 3 · 자동 원복.",
    )


# ════════════════════════════════════════════════════════════════════════
# 시나리오 5 — GCP Cloud Function 장애
# ════════════════════════════════════════════════════════════════════════
def _s5_cf_errors_stat():
    """현재 상태 — Cloud Function 에러 호출 수 (status!=ok).

    placeholder 가능: admin EKS 클러스터에서 GCP datasource 의 oauth2 토큰
    교환 egress 가 차단돼 라이브 검증 불가(2026-05-19). 쿼리 형태는 Row 3
    검증분과 동일 — deploy 환경/네트워크 허용 시 동작한다.
    """
    p = pb.stat_panel(
        "① 현재 상태 · CF 에러 호출 수",
        unit="short",
        color_mode=pb.BigValueColorMode.VALUE,
        thresholds=pb._thresholds([(None, pb.GREEN), (1, pb.YELLOW), (5, pb.RED)]),
        mappings=[_NODATA_MAP],
        description=(
            "cloudfunctions execution_count · status!=ok 합계. "
            "0=정상. placeholder — admin GCP oauth egress 차단."
        ),
    )
    return p.datasource(_gcp()).with_target(
        _gcp_ts(
            "cloudfunctions.googleapis.com/function/execution_count",
            aligner="ALIGN_SUM", reducer="REDUCE_SUM",
            extra_filters=['metric.label.status!="ok"'],
            alias="에러 호출",
        )
    )


def _s5_cf_timeline():
    """발생→복구 — Cloud Function 호출 status 별 추세. 에러 스파이크."""
    p = pb.timeseries_panel(
        "② 발생→복구 · CF 호출 status 별 (에러 스파이크)",
        unit="short",
        span=pb.SPAN_HALF,
        fill_opacity=20,
        description=(
            "cloudfunctions execution_count · status 별 ALIGN_SUM. "
            "bq-load 등 함수 장애 시 error/timeout status 스파이크. "
            "placeholder — admin GCP oauth egress 차단(Row 3 와 동일 쿼리)."
        ),
    )
    return p.datasource(_gcp()).with_target(
        _gcp_ts(
            "cloudfunctions.googleapis.com/function/execution_count",
            aligner="ALIGN_SUM", reducer="REDUCE_SUM",
            group_bys=["metric.label.status"],
            alias="{{metric.label.status}}",
            alignment_period="+3600s",
        )
    )


def _s5_cf_byfunc():
    """발생→복구 — 함수별 호출 수. 어느 함수가 죽었는지."""
    p = pb.timeseries_panel(
        "② CF 함수별 호출 수",
        unit="short",
        span=pb.SPAN_QUARTER,
        description=(
            "cloudfunctions execution_count · function_name 별. "
            "bq-load·feature-assemble·vertex-invoke. placeholder."
        ),
    )
    return p.datasource(_gcp()).with_target(
        _gcp_ts(
            "cloudfunctions.googleapis.com/function/execution_count",
            aligner="ALIGN_SUM", reducer="REDUCE_SUM",
            group_bys=["resource.label.function_name"],
            alias="{{resource.label.function_name}}",
            alignment_period="+3600s",
        )
    )


def _s5_trigger():
    return _trigger_text(
        "③ 트리거 — GCP Cloud Function",
        "**실행 로그 확인**\n```\ngcloud functions logs read bq-load \\\n"
        "  --region asia-northeast1 --limit 50\n```\n"
        "**기대**: 에러 로그 발생 시 status!=ok 스파이크 · BQ 적재 지연.",
    )


# ════════════════════════════════════════════════════════════════════════
# 시나리오 6 — GCP VPN 터널 장애
# ════════════════════════════════════════════════════════════════════════
def _s6_vpn_state():
    """현재 상태 — AWS↔GCP VPN 터널 UP/DOWN 신호등."""
    p = pb.stat_panel(
        "① 현재 상태 · AWS↔GCP VPN 터널",
        mappings=[_UPDOWN_MAP, _NODATA_MAP],
        thresholds=pb.updown_thresholds(),
        graph_mode=BigValueGraphMode.NONE,
        description=(
            "AWS/VPN TunnelState · Maximum (터널 중 하나라도 UP 이면 1). "
            "AWS↔GCP HA VPN."
        ),
    )
    return p.datasource(_cw()).with_target(
        _cw_metric("A", "AWS/VPN", "TunnelState",
                   {"VpnId": VPN_AWS_GCP}, stat="Maximum", label="AWS↔GCP")
    )


def _s6_vpn_timeline():
    """발생→복구 — 터널 상태 타임라인. 끊김→복구."""
    p = pb.timeseries_panel(
        "② 발생→복구 · VPN 터널 상태 (끊김→복구)",
        unit="short",
        span=pb.SPAN_HALF,
        thresholds=pb.updown_thresholds(),
        description=(
            "AWS/VPN TunnelState — 1=UP/0=DOWN. 터널 장애 시 0 으로 떨어졌다 "
            "재협상 후 1 로 복구되는 게 보인다."
        ),
    )
    return p.datasource(_cw()).with_target(
        _cw_metric("A", "AWS/VPN", "TunnelState",
                   {"VpnId": VPN_AWS_GCP}, stat="Maximum", label="터널 상태")
    )


def _s6_vpn_traffic():
    """발생→복구 — 터널 트래픽. 장애 구간 데이터 흐름 멈춤."""
    p = pb.timeseries_panel(
        "② VPN 터널 트래픽 (In/Out)",
        unit="bytes",
        span=pb.SPAN_QUARTER,
        description="AWS/VPN TunnelDataIn·Out — 장애 구간엔 트래픽이 멈춘다.",
    )
    return (
        p.datasource(_cw())
        .with_target(_cw_metric("A", "AWS/VPN", "TunnelDataIn",
                                {"VpnId": VPN_AWS_GCP}, stat="Sum", label="In"))
        .with_target(_cw_metric("B", "AWS/VPN", "TunnelDataOut",
                                {"VpnId": VPN_AWS_GCP}, stat="Sum", label="Out"))
    )


def _s6_trigger():
    return _trigger_text(
        "③ 트리거 — GCP VPN 터널",
        "**터널 상태 확인**\n```\naws ec2 describe-vpn-connections \\\n"
        "  --region ap-northeast-1\ngcloud compute vpn-tunnels list \\\n"
        "  --region asia-northeast1\n```\n"
        "**기대**: 장애 시 forecast-svc BigQuery 연결 실패.",
    )


# ════════════════════════════════════════════════════════════════════════
# 시나리오 7 — Azure Logic Apps 장애 (2026-05-19 실제 사건 재현)
# ════════════════════════════════════════════════════════════════════════
def _s7_logic_failed_stat():
    """현재 상태 — 최근 1h Logic App 실패 실행 수.

    2026-05-19 실사건: stock-depart/arrival 14건 동시 실패·429·504.
    """
    kql = (
        "AzureDiagnostics "
        "| where ResourceProvider == 'MICROSOFT.LOGIC' "
        "| where TimeGenerated > ago(1h) "
        "| summarize 실패=countif(status_s=='Failed') "
        "| project 실패"
    )
    p = pb.stat_panel(
        "① 현재 상태 · Logic App 실패 (1h)",
        unit="short",
        color_mode=pb.BigValueColorMode.VALUE,
        thresholds=pb._thresholds([(None, pb.GREEN), (1, pb.YELLOW), (5, pb.RED)]),
        mappings=[_NODATA_MAP],
        description=(
            "AzureDiagnostics MICROSOFT.LOGIC 최근 1h Failed 실행 수. "
            "2026-05-19 실사건: 14건 동시 실패(429 rate limit)."
        ),
    )
    return p.datasource(_azure()).with_target(
        _azure_logs(kql, ResultFormat.TABLE)
    )


def _s7_logic_timeline():
    """발생→복구 — Logic App 실행 status 별 추세. 14건 동시 실패 스파이크.

    2026-05-19 13:47~48 stock-depart/arrival 동시 실패가 그래프로 재현된다.
    세마포어 fix 후엔 Failed 시리즈가 0 으로 정상화.
    """
    kql = (
        "AzureDiagnostics "
        "| where ResourceProvider == 'MICROSOFT.LOGIC' "
        "| where TimeGenerated > ago(6h) "
        "| summarize 완료=countif(status_s=='Succeeded'), "
        "실패=countif(status_s=='Failed') "
        "by bin(TimeGenerated, 5m) "
        "| order by TimeGenerated asc"
    )
    p = pb.timeseries_panel(
        "② 발생→복구 · Logic App 실행 (완료/실패 · 동시 실패 스파이크)",
        unit="short",
        span=pb.SPAN_HALF,
        fill_opacity=20,
        description=(
            "AzureDiagnostics WorkflowRuntime 5m 집계. 2026-05-19 실사건의 "
            "14건 동시 실패 스파이크 재현 · 세마포어 fix 후 Failed 0 정상화."
        ),
    )
    return p.datasource(_azure()).with_target(
        _azure_logs(kql, ResultFormat.TIME_SERIES)
    )


def _s7_logic_failures_table():
    """발생→복구 — 워크플로별 실패 + 429/타임아웃 상세."""
    kql = (
        "AzureDiagnostics "
        "| where ResourceProvider == 'MICROSOFT.LOGIC' "
        "| where TimeGenerated > ago(6h) "
        "| summarize 실행=count(), "
        "성공=countif(status_s=='Succeeded'), "
        "실패=countif(status_s=='Failed') "
        "by 워크플로=resource_workflowName_s "
        "| where 실패 > 0 or 실행 > 0 "
        "| order by 실패 desc, 실행 desc"
    )
    p = pb.table_panel(
        "② 워크플로별 실행/실패 현황",
        span=pb.SPAN_QUARTER,
        description=(
            "AzureDiagnostics 6h — 워크플로별 실행/성공/실패. "
            "stock-depart·stock-arrival 의 동시 실패가 표로."
        ),
    )
    return p.datasource(_azure()).with_target(
        _azure_logs(kql, ResultFormat.TABLE)
    )


def _s7_trigger():
    return _trigger_text(
        "③ 트리거 — Azure Logic Apps",
        "**다수 알림 동시 발송 (15건)**\n```\nfor i in $(seq 1 15); do\n"
        "  kubectl exec -n bookflow deploy/notification-svc -- \\\n"
        "    curl -sX POST localhost:8080/notify ... &\ndone; wait\n```\n"
        "**기대**: 429 rate limit → 504 (세마포어 fix 후 정상).",
    )


# ════════════════════════════════════════════════════════════════════════
# 시나리오 8 — Client VPN 장애
# ════════════════════════════════════════════════════════════════════════
def _s8_clientvpn_stat():
    """현재 상태 — Client VPN 활성 연결 수.

    placeholder: admin 계정에 Client VPN endpoint 메트릭 미발행(2026-05-19
    라이브 실측 — SEARCH 결과 0 frame). Client VPN 은 Phase 기반 자원 —
    배포·연결 시 AWS/ClientVPN ActiveConnectionsCount 가 발행돼 동작한다.
    """
    p = pb.stat_panel(
        "① 현재 상태 · Client VPN 활성 연결",
        unit="short",
        color_mode=pb.BigValueColorMode.VALUE,
        thresholds=pb._thresholds([(None, pb.RED), (1, pb.GREEN)]),
        mappings=[_NODATA_MAP],
        description=(
            "AWS/ClientVPN ActiveConnectionsCount SEARCH 합계. "
            "placeholder — admin 계정 Client VPN endpoint 메트릭 미발행."
        ),
    )
    return p.datasource(_cw()).with_target(
        _cw_search(
            "A", "AWS/ClientVPN",
            "SEARCH('{AWS/ClientVPN,Endpoint} "
            "MetricName=\"ActiveConnectionsCount\"', 'Average', 300)",
            stat="Average", label="활성 연결",
        )
    )


def _s8_clientvpn_timeline():
    """발생→복구 — Client VPN 연결 수 추세. 연결 끊김.

    placeholder — admin 계정 Client VPN endpoint 메트릭 미발행(위 stat 참조).
    """
    p = pb.timeseries_panel(
        "② 발생→복구 · Client VPN 연결 수 (끊김)",
        unit="short",
        span=pb.SPAN_HALF,
        fill_opacity=20,
        description=(
            "AWS/ClientVPN ActiveConnectionsCount·AuthenticationFailures "
            "SEARCH. 담당자 연결 끊김이 추세로. placeholder — 메트릭 미발행."
        ),
    )
    return (
        p.datasource(_cw())
        .with_target(_cw_search(
            "A", "AWS/ClientVPN",
            "SEARCH('{AWS/ClientVPN,Endpoint} "
            "MetricName=\"ActiveConnectionsCount\"', 'Average', 300)",
            stat="Average", label="활성 연결"))
        .with_target(_cw_search(
            "B", "AWS/ClientVPN",
            "SEARCH('{AWS/ClientVPN,Endpoint} "
            "MetricName=\"AuthenticationFailures\"', 'Sum', 300)",
            stat="Sum", label="인증 실패"))
    )


def _s8_clientvpn_traffic():
    """발생→복구 — Client VPN 수신/송신 트래픽."""
    p = pb.timeseries_panel(
        "② Client VPN 트래픽 (In/Out)",
        unit="bytes",
        span=pb.SPAN_QUARTER,
        description=(
            "AWS/ClientVPN IngressBytes·EgressBytes SEARCH. "
            "placeholder — admin 계정 메트릭 미발행."
        ),
    )
    return (
        p.datasource(_cw())
        .with_target(_cw_search(
            "A", "AWS/ClientVPN",
            "SEARCH('{AWS/ClientVPN,Endpoint} "
            "MetricName=\"IngressBytes\"', 'Sum', 300)",
            stat="Sum", label="In"))
        .with_target(_cw_search(
            "B", "AWS/ClientVPN",
            "SEARCH('{AWS/ClientVPN,Endpoint} "
            "MetricName=\"EgressBytes\"', 'Sum', 300)",
            stat="Sum", label="Out"))
    )


def _s8_trigger():
    return _trigger_text(
        "③ 트리거 — Client VPN",
        "**Client VPN endpoint 상태 확인**\n```\n"
        "aws ec2 describe-client-vpn-endpoints \\\n"
        "  --region ap-northeast-1\naws ec2 \\\n"
        "  describe-client-vpn-connections \\\n"
        "  --client-vpn-endpoint-id <id>\n```\n"
        "**기대**: 연결 끊김 시 ActiveConnectionsCount 하락.",
    )


# ════════════════════════════════════════════════════════════════════════
def dashboard() -> Dashboard:
    """Row 9 (장애 시나리오·복원력) 대시보드 빌더를 반환. build.py 가 호출."""
    return (
        base_dashboard(TITLE, UID, DESCRIPTION)
        # ── 시나리오 1 — EKS Pod 장애 ──────────────────────────────────
        .with_row(Row("시나리오 1 · EKS Pod 장애 — Pod 죽음→재생성 (무중단)"))
        .with_panel(_s1_pod_health())
        .with_panel(_s1_pod_restarts())
        .with_panel(_s1_trigger())
        .with_panel(_s1_pod_timeline())
        # ── 시나리오 2 — 노드 오토스케일링 ────────────────────────────
        .with_row(Row("시나리오 2 · 노드 오토스케일링 — drain→scale-up"))
        .with_panel(_s2_node_count())
        .with_panel(_s2_pod_distribution())
        .with_panel(_s2_trigger())
        .with_panel(_s2_node_timeline())
        # ── 시나리오 3 — RDS Failover ──────────────────────────────────
        .with_row(Row("시나리오 3 · RDS Failover — Multi-AZ 이중화"))
        .with_panel(_s3_rds_connections())
        .with_panel(_s3_rds_writeio())
        .with_panel(_s3_trigger())
        .with_panel(_s3_rds_timeline())
        # ── 시나리오 4 — Publisher ASG ─────────────────────────────────
        .with_row(Row("시나리오 4 · Publisher ASG — EC2 오토스케일 아웃 2→3"))
        .with_panel(_s4_asg_capacity())
        .with_panel(_s4_trigger())
        .with_panel(_s4_asg_timeline())
        # ── 시나리오 5 — GCP Cloud Function ────────────────────────────
        .with_row(Row("시나리오 5 · GCP Cloud Function 장애 — 에러 스파이크"))
        .with_panel(_s5_cf_errors_stat())
        .with_panel(_s5_cf_byfunc())
        .with_panel(_s5_trigger())
        .with_panel(_s5_cf_timeline())
        # ── 시나리오 6 — GCP VPN 터널 ──────────────────────────────────
        .with_row(Row("시나리오 6 · GCP VPN 터널 장애 — AWS↔GCP 끊김→복구"))
        .with_panel(_s6_vpn_state())
        .with_panel(_s6_vpn_traffic())
        .with_panel(_s6_trigger())
        .with_panel(_s6_vpn_timeline())
        # ── 시나리오 7 — Azure Logic Apps ──────────────────────────────
        .with_row(Row("시나리오 7 · Azure Logic Apps 장애 — 2026-05-19 실사건 재현"))
        .with_panel(_s7_logic_failed_stat())
        .with_panel(_s7_logic_failures_table())
        .with_panel(_s7_trigger())
        .with_panel(_s7_logic_timeline())
        # ── 시나리오 8 — Client VPN ────────────────────────────────────
        .with_row(Row("시나리오 8 · Client VPN 장애 — 담당자 연결 끊김"))
        .with_panel(_s8_clientvpn_stat())
        .with_panel(_s8_clientvpn_traffic())
        .with_panel(_s8_trigger())
        .with_panel(_s8_clientvpn_timeline())
    )
