"""task-data · Tier 20 RDS + Redis + Kinesis."""
from ..lib import Stack, log


def deploy() -> None:
    log.step("=== task-data · RDS + Redis + Kinesis ===")
    if not Stack(tier="10", name="vpc-data", template="").exists():
        log.err("Tier 10 vpc-data  · base-up  ")
        raise SystemExit(1)

    Stack(tier="20", name="rds", template="20-data-persistent/rds.yaml",
          parameters={"EnableMultiAz": "false"}).deploy()
    Stack(tier="20", name="redis", template="20-data-persistent/redis.yaml",
          parameters={"EnableReplication": "false"}).deploy()
    Stack(tier="20", name="kinesis", template="20-data-persistent/kinesis.yaml").deploy()

    log.step("=== task-data  ===")


def destroy() -> None:
    log.step("=== task-data-down ===")
    Stack(tier="20", name="kinesis", template="").destroy()
    Stack(tier="20", name="redis", template="").destroy()
    Stack(tier="20", name="rds", template="").destroy()
    log.step("=== task-data-down  ===")
