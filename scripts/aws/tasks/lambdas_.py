"""task-lambdas · Tier 99-serverless (7 Lambdas + EventBridge + Kinesis ESM + API Gateway).

SAM template 으로 deploy.
"""
from ..lib import Stack, log


def deploy() -> None:
    log.step("=== task-lambdas · 7 Lambdas SAM ===")
    if not Stack(tier="10", name="vpc-bookflow-ai", template="").exists():
        log.err("vpc-bookflow-ai 미배포"); raise SystemExit(1)
    if not Stack(tier="20", name="kinesis", template="").exists():
        log.err("kinesis 미배포 · task-data 먼저"); raise SystemExit(1)
    if not Stack(tier="20", name="rds", template="").exists():
        log.warn("RDS 미배포 · pos-ingestor / spike-detect 동작 안함")
    if not Stack(tier="10", name="peering-bookflow-ai-data", template="").exists():
        log.warn("peering bookflow-ai-data 미배포 · pos-ingestor → RDS 단절")

    sf_arn = Stack(tier="99", name="step-functions", template="").outputs().get("Etl3StateMachineArn", "")

    params = {}
    if sf_arn:
        params["StepFunctionsArn"] = sf_arn

    Stack(tier="99", name="lambdas",
          template="99-serverless/sam-template.yaml",
          parameters=params,
          capabilities=["CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND", "CAPABILITY_IAM"]
          ).deploy()

    out = Stack(tier="99", name="lambdas", template="").outputs()
    log.info(f"secret-forwarder API: {out.get('SecretForwarderApiUrl', '?')}")
    log.step("=== task-lambdas 완료 ===")


def destroy() -> None:
    log.step("=== task-lambdas-down ===")
    Stack(tier="99", name="lambdas", template="").destroy()
    log.step("=== task-lambdas-down 완료 ===")
