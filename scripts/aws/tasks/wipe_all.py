"""wipe-all · 모든 자원 (Tier 00 영구 포함) destroy. 프로젝트 완전 종료 시.

⚠️ 강력 confirmation 필요 · S3 객체 / ECR 이미지 사전 삭제 필요.
"""
from ..lib import log
from . import base, foundation


def deploy() -> None:
    raise SystemExit("wipe-all 은 destroy 전용. `phase0` + `task` 등으로 deploy.")


def destroy() -> None:
    log.step("=== WIPE ALL · 모든 BOOKFLOW 자원 제거 ===")
    log.warn("S3 객체 / ECR 이미지 / KMS pending / ACM IN_USE · 사전 정리 필요")
    confirm = input("정말 진행? 'WIPE EVERYTHING' 입력 → ").strip()
    if confirm != "WIPE EVERYTHING":
        log.info("취소")
        return

    log.info("1. base-down (Tier 10-99)")
    base.destroy()
    log.info("2. phase0-foundation-down (Tier 00 영구)")
    foundation.destroy()
    log.step("=== WIPE ALL 완료 ===")
