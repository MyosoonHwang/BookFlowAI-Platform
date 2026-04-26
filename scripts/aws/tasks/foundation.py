"""Tier 00 · Foundation (영구 자원 · Day 0 1회).

KMS · S3 · Secrets · ACM · ECR · IAM OIDC · CodeStar · CloudTrail · CloudWatch.
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
    ("cloudtrail",          "00-foundation/cloudtrail.yaml"),
    ("cloudwatch",          "00-foundation/cloudwatch.yaml"),
]


def deploy() -> None:
    log.step("═══ Phase 0 · Foundation Deploy (영구 자원 · Day 0 1회) ═══")
    for name, template in STACKS:
        Stack(tier="00", name=name, template=template).deploy()
    log.warn("CodeStar Connection 은 PENDING 상태로 생성됨 · Console 에서 수동 Activate 필요")
    log.step("═══ Tier 00 Foundation 배포 완료 ═══")


def destroy() -> None:
    log.step("═══ Tier 00 Foundation Destroy (영구 자원 ⚠) ═══")
    for name, _template in reversed(STACKS):
        Stack(tier="00", name=name, template="").destroy()
    log.step("═══ Tier 00 destroy 완료 ═══")
