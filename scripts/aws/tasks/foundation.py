"""Tier 00 · Foundation (  · Day 0 1).

 STACKS: KMS · IAM · Parameter Store · Secrets · ACM · ECR · CodeStar · S3.
 STACKS (/ ): CloudTrail · CloudWatch — phase0 default   ·
  STACKS_OPTIONAL  stack   deploy.
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

# / — audit bucket  (S3 Object Lock 90) ·    deploy
STACKS_OPTIONAL = [
    ("cloudtrail",          "00-foundation/cloudtrail.yaml"),
    ("cloudwatch",          "00-foundation/cloudwatch.yaml"),
]


def deploy() -> None:
    log.step("═══ Phase 0 · Foundation Deploy (  · Day 0 1) ═══")
    for name, template in STACKS:
        Stack(tier="00", name=name, template=template).deploy()
    log.warn("CodeStar Connection  PENDING   · Console   Activate ")
    log.warn("CloudTrail · CloudWatch  default skip ·   STACKS_OPTIONAL  deploy")
    log.warn("Audit S3 bucket: phase0 default skip · `s3.yaml` EnableAuditBucket=true  ")
    log.step("═══ Tier 00 Foundation   ═══")


def destroy() -> None:
    log.step("═══ Tier 00 Foundation Destroy (  ⚠) ═══")
    # OPTIONAL    ( destroy ·  no-op)
    for name, _template in reversed(STACKS + STACKS_OPTIONAL):
        Stack(tier="00", name=name, template="").destroy()
    log.step("═══ Tier 00 destroy  ═══")
