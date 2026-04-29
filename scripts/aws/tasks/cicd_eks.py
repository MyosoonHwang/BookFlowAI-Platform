"""cicd-eks · CodePipeline + CodeBuild for BookFlowAI-Apps eks-pods

Stack 이름: bookflow-cicd-eks
Template:  cicd/codepipeline/eks-pipeline.yaml

Deploy 흐름:
  1. eks-pipeline stack create
  2. CodeBuildRoleArn 출력 → eks-cluster stack 에 update-stack 으로 주입 (Access Entry 활성화)

사전 조건:
  - Tier 00 codestar-connection · ecr · iam (이미 deploy)
  - Tier 30 eks-cluster (현재 ACTIVE 상태)
  - BookFlowAI-Apps repo 의 main 브랜치에 eks-pods/ 와 buildspec.yml 존재

라이프사이클: 🟡 필요 시 deploy
"""
import boto3

from ..lib import Stack, log
from ..lib.config import Config

CICD_ROOT = Config.REPO_ROOT / "cicd" / "codepipeline"


def deploy() -> None:
    log.step("=== cicd-eks · CodePipeline + CodeBuild deploy ===")

    # 1. CICD stack
    cicd_stack = Stack(
        tier="cicd",
        name="eks",
        template="eks-pipeline.yaml",
        template_root=CICD_ROOT,
    )
    cicd_stack.deploy()

    # 2. CodeBuild role ARN 추출 → eks-cluster 에 주입
    out = cicd_stack.outputs()
    cb_role_arn = out.get("CodeBuildRoleArn")
    if not cb_role_arn:
        log.warn("CodeBuildRoleArn output 없음 · Access Entry 수동 설정 필요")
        return

    log.info(f"CodeBuildRoleArn: {cb_role_arn}")

    # 3. eks-cluster stack 에 update-stack (CiCdRoleArn 주입 → AccessEntry 활성화)
    cf = boto3.client("cloudformation", region_name=Config.REGION)
    cluster_stack_name = Config.stack_name("30", "eks-cluster")

    try:
        existing = cf.describe_stacks(StackName=cluster_stack_name)
        existing_params = existing["Stacks"][0].get("Parameters", [])
        current_role = next((p["ParameterValue"] for p in existing_params
                            if p["ParameterKey"] == "CiCdRoleArn"), "")
        if current_role == cb_role_arn:
            log.info(f"  eks-cluster CiCdRoleArn already up-to-date · skip")
            return
    except cf.exceptions.ClientError as e:
        if "does not exist" in str(e):
            log.warn(f"  {cluster_stack_name} 미존재 · Access Entry 주입 skip (cluster deploy 후 재실행)")
            return
        raise

    log.step(f"Update {cluster_stack_name} · inject CiCdRoleArn")
    cf.update_stack(
        StackName=cluster_stack_name,
        UsePreviousTemplate=True,
        Parameters=[
            {"ParameterKey": "CiCdRoleArn", "ParameterValue": cb_role_arn,
             "UsePreviousValue": False},
            # 다른 모든 parameter 는 그대로 유지
            *[{"ParameterKey": p["ParameterKey"], "UsePreviousValue": True}
              for p in existing_params if p["ParameterKey"] != "CiCdRoleArn"],
        ],
        Capabilities=["CAPABILITY_NAMED_IAM"],
    )
    cf.get_waiter("stack_update_complete").wait(
        StackName=cluster_stack_name,
        WaiterConfig={"Delay": 15, "MaxAttempts": 60},
    )
    log.success(f"  {cluster_stack_name} CiCdRoleArn injected (Access Entry active)")

    log.step("=== cicd-eks deploy 완료 ===")


def destroy() -> None:
    log.step("=== cicd-eks destroy ===")

    # 1. eks-cluster 의 CiCdRoleArn 비우기 (Access Entry 제거 · stack 미존재면 skip)
    cf = boto3.client("cloudformation", region_name=Config.REGION)
    cluster_stack_name = Config.stack_name("30", "eks-cluster")
    try:
        existing = cf.describe_stacks(StackName=cluster_stack_name)
        existing_params = existing["Stacks"][0].get("Parameters", [])
        current_role = next((p["ParameterValue"] for p in existing_params
                            if p["ParameterKey"] == "CiCdRoleArn"), "")
        if current_role:
            log.step(f"Update {cluster_stack_name} · clear CiCdRoleArn (Access Entry off)")
            cf.update_stack(
                StackName=cluster_stack_name,
                UsePreviousTemplate=True,
                Parameters=[
                    {"ParameterKey": "CiCdRoleArn", "ParameterValue": "",
                     "UsePreviousValue": False},
                    *[{"ParameterKey": p["ParameterKey"], "UsePreviousValue": True}
                      for p in existing_params if p["ParameterKey"] != "CiCdRoleArn"],
                ],
                Capabilities=["CAPABILITY_NAMED_IAM"],
            )
            cf.get_waiter("stack_update_complete").wait(
                StackName=cluster_stack_name,
                WaiterConfig={"Delay": 15, "MaxAttempts": 60},
            )
    except cf.exceptions.ClientError as e:
        if "does not exist" in str(e):
            log.info(f"  {cluster_stack_name} 미존재 · cluster cleanup skip")
        else:
            raise

    # 2. CICD stack 삭제
    Stack(tier="cicd", name="eks", template="").destroy()

    log.step("=== cicd-eks destroy 완료 ===")
