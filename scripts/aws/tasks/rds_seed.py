"""task-rds-seed · Ansible playbook 으로 RDS schema/seed 주입.

현재 placeholder · ansible playbook 미작성. peering 만 deploy + SSM 명령 안내.
"""
import boto3

from ..lib import Config, Stack, log


def deploy() -> None:
    log.step("=== task-rds-seed · Ansible playbook trigger ===")
    if not Stack(tier="20", name="rds", template="").exists():
        log.err("rds 미배포 · task-data 먼저"); raise SystemExit(1)
    if not Stack(tier="30", name="ansible-node", template="").exists():
        log.err("ansible-node 미배포 · base-up 먼저"); raise SystemExit(1)

    Stack(tier="10", name="peering-ansible-data",
          template="10-network-core/peering/ansible-data.yaml").deploy()

    instance_id = Stack(tier="30", name="ansible-node", template="").outputs().get("InstanceId")
    if not instance_id:
        log.err("Ansible Node InstanceId 조회 실패"); raise SystemExit(1)
    log.info(f"Ansible Node: {instance_id}")

    log.warn("Ansible playbook 미작성 (placeholder)")
    log.info(f"  aws ssm send-command --instance-ids {instance_id} \\")
    log.info('    --document-name "AWS-RunShellScript" \\')
    log.info('    --parameters \'commands=["cd /opt/bookflow && ansible-playbook cicd/ansible/rds-seed.yml"]\'')
    log.step("=== task-rds-seed 완료 (placeholder) ===")


def destroy() -> None:
    log.step("=== task-rds-seed-down · peering-ansible-data ===")
    Stack(tier="10", name="peering-ansible-data", template="").destroy()
    log.step("=== task-rds-seed-down 완료 ===")
