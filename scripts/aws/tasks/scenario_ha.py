"""task-scenario-ha · RDS Multi-AZ + Redis ReplicationGroup 전환.

Revert: --revert 로 single-AZ + single-node 복귀.
"""
from ..lib import Stack, log


def deploy() -> None:
    log.step("=== HA 전환 · RDS Multi-AZ + Redis Replication ===")
    log.warn("Redis SingleNode → ReplicationGroup 은 resource replacement (cache 소실)")
    log.warn("RDS Multi-AZ 전환은 in-place modify (~5-10분)")

    Stack(tier="20", name="rds", template="20-data-persistent/rds.yaml",
          parameters={"EnableMultiAz": "true"}).deploy()
    Stack(tier="20", name="redis", template="20-data-persistent/redis.yaml",
          parameters={"EnableReplication": "true"}).deploy()

    log.step("=== HA 전환 완료 ===")


def destroy() -> None:
    """Revert: HA → 구축 모드 (Single-AZ · SingleNode)."""
    log.step("=== HA revert · Single-AZ + SingleNode 복귀 ===")
    Stack(tier="20", name="rds", template="20-data-persistent/rds.yaml",
          parameters={"EnableMultiAz": "false"}).deploy()
    Stack(tier="20", name="redis", template="20-data-persistent/redis.yaml",
          parameters={"EnableReplication": "false"}).deploy()
    log.step("=== HA revert 완료 ===")
