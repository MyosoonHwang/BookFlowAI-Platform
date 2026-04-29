"""Tier 00 · Foundation (영구 자원 · Day 0 1회).

기본 STACKS: KMS · IAM · Parameter Store · Secrets · ACM · ECR · CodeStar · S3.
선택 STACKS (감사/관측 용도): CloudTrail · CloudWatch — phase0 default 에 미포함 ·
필요 시 STACKS_OPTIONAL 의 stack 만 직접 deploy.
"""
from ..lib import Stack, log


STACKS = [
    ("iam",                 "00-foundation/iam.yaml"),
    ("kms",                 "00-foundation/kms.yaml"),
    ("parameter-store",     "00-foundation/parameter-store.yaml"),
    ("secrets",             "00-foundation/secrets.yaml"),
    ("acm",                 "00-foundation/acm.yaml"),
    ("ecr",                 "00-foundation/ecr.yaml"),
    ("codestar-connection", "00-foundation/codestar-connection.yaml"),
    ("s3",                  "00-foundation/s3.yaml"),
]

# 감사/관측 — audit bucket 사용 (S3 Object Lock 90일) · 필요 시 별도 deploy
STACKS_OPTIONAL = [
    ("cloudtrail",          "00-foundation/cloudtrail.yaml"),
    ("cloudwatch",          "00-foundation/cloudwatch.yaml"),
]


def deploy() -> None:
    log.step("═══ Phase 0 · Foundation Deploy (영구 자원 · Day 0 1회) ═══")
    for name, template in STACKS:
        Stack(tier="00", name=name, template=template).deploy()
    log.warn("CodeStar Connection 은 PENDING 상태로 생성됨 · Console 에서 수동 Activate 필요")
    log.warn("CloudTrail · CloudWatch 는 default skip · 필요 시 STACKS_OPTIONAL 별도 deploy")
    log.warn("Audit S3 bucket: phase0 default skip · `s3.yaml` EnableAuditBucket=true 로 활성화")
    log.step("═══ Tier 00 Foundation 배포 완료 ═══")


def destroy() -> None:
    log.step("═══ Tier 00 Foundation Destroy (영구 자원 ⚠) ═══")
    # OPTIONAL 도 같이 정리 (있으면 destroy · 없으면 no-op)
    for name, _template in reversed(STACKS + STACKS_OPTIONAL):
        Stack(tier="00", name=name, template="").destroy()
    log.step("═══ Tier 00 destroy 완료 ═══")
