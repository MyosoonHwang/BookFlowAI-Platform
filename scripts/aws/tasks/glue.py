"""task-glue · Tier 99-glue (Catalog + 6 Jobs + Step Functions ETL3)."""
from ..lib import Stack, log


def deploy() -> None:
    log.step("=== task-glue · Glue Catalog + 6 Jobs + Step Functions ===")

    Stack(tier="99", name="glue-catalog",
          template="99-glue/glue-catalog.yaml").deploy()
    Stack(tier="99", name="step-functions",
          template="99-glue/step-functions.yaml").deploy()

    sf_arn = Stack(tier="99", name="step-functions", template="").outputs().get("Etl3StateMachineArn")

    if Stack(tier="99", name="lambdas", template="").exists() and sf_arn:
        log.info("task-lambdas 이미 deploy 됨 → forecast-trigger 에 SF ARN 주입")
        Stack(tier="99", name="lambdas",
              template="99-serverless/sam-template.yaml",
              parameters={"StepFunctionsArn": sf_arn},
              capabilities=["CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND", "CAPABILITY_IAM"]
              ).deploy()
    else:
        log.info("task-lambdas 미배포 · 추후 task-lambdas 실행 시 SF ARN 자동 주입")

    log.step("=== task-glue 완료 ===")
    if sf_arn:
        log.info(f"ETL3 SF ARN: {sf_arn}")


def destroy() -> None:
    log.step("=== task-glue-down ===")
    Stack(tier="99", name="step-functions", template="").destroy()
    Stack(tier="99", name="glue-catalog", template="").destroy()
    log.step("=== task-glue-down 완료 ===")
