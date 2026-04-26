"""task-full-stack · 모든 task 한방에 (data → msa-pods → etl-streaming → publisher).

cross-cloud (auth-pod / forecast / client-vpn) 와 rds-seed 는 별도.
"""
from ..lib import log
from . import data, etl_streaming, msa_pods, publisher


def deploy() -> None:
    log.step("=== task-full-stack · 통합 deploy ===")
    data.deploy()
    msa_pods.deploy()
    etl_streaming.deploy()
    publisher.deploy()
    log.step("=== task-full-stack 완료 ===")


def destroy() -> None:
    """모든 task 자원 destroy (base 는 유지). base-down 으로 base 까지 정리."""
    log.step("=== task-full-stack-down · 모든 task 자원 destroy ===")
    from . import auth_pod, client_vpn, forecast, glue, lambdas_, rds_seed
    glue.destroy()
    lambdas_.destroy()
    publisher.destroy()
    etl_streaming.destroy()
    rds_seed.destroy()
    msa_pods.destroy()
    data.destroy()
    client_vpn.destroy()
    forecast.destroy()
    auth_pod.destroy()
    log.step("=== task-full-stack-down 완료 ===")
