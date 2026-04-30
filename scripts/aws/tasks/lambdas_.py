"""task-lambdas · Tier 99-serverless (7 Lambdas + EventBridge + Kinesis ESM + API Gateway).

SAM template  deploy.
"""
from ..lib import Stack, log


def deploy() -> None:
    log.step("=== task-lambdas · 7 Lambdas SAM ===")
    if not Stack(tier="10", name="vpc-bookflow-ai", template="").exists():
        log.err("vpc-bookflow-ai "); raise SystemExit(1)
    if not Stack(tier="20", name="kinesis", template="").exists():
        log.err("kinesis  · task-data "); raise SystemExit(1)
    if not Stack(tier="20", name="rds", template="").exists():
        log.warn("RDS  · pos-ingestor / spike-detect  ")
    if not Stack(tier="10", name="peering-bookflow-ai-data", template="").exists():
        log.warn("peering bookflow-ai-data  · pos-ingestor → RDS ")

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
    log.step("=== task-lambdas  ===")


def destroy() -> None:
    log.step("=== task-lambdas-down ===")
    Stack(tier="99", name="lambdas", template="").destroy()
    log.step("=== task-lambdas-down  ===")
