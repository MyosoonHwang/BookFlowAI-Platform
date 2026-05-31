"""ping-test · Azure/GCP 통신 검증용 VPC + EC2(t3.micro) 배포.

── 목적 ──────────────────────────────────────────────────────────────
  VPN failover 검증 시 데이터 플레인(실제 패킷) 통신을 확인하기 위한
  테스트 전용 경량 인프라. 프로덕션 VPC와 분리된 독립 VPC를 사용.

── 생성 리소스 ────────────────────────────────────────────────────────
  VPC 10.100.0.0/24
    └─ 퍼블릭 서브넷 + IGW (EC2에 공인 IP 자동 부여 → SSH 접속 가능)
  TGW attachment → 아래 두 대역으로 가는 경로를 TGW 경유로 설정
    · Azure VNet : 172.16.0.0/16
    · GCP VPC    : 192.168.10.0/24
  EC2 t3.micro (Amazon Linux 2023, SSH 접속)
    · 인바운드: ICMP(ping 수신) + TCP 22(SSH) 허용
    · 아웃바운드: 전체 허용 (TGW 경유 Azure/GCP로 ICMP 패킷 전송)

── SSH vs SSM ────────────────────────────────────────────────────────
  SSH  : 클라이언트가 EC2의 22번 포트에 직접 TCP 연결.
         인바운드 22번 보안그룹 규칙 + 키 파일(.pem) 필요.
  SSM  : EC2 Agent가 아웃바운드로 AWS SSM 엔드포인트에 연결.
         인바운드 포트 불필요, IAM Role로 인증.
  → 이 스크립트는 SSH 방식을 사용 (직관적인 터미널 접속 + ping 출력 실시간 확인).

── ping과 ICMP 프로토콜 ─────────────────────────────────────────────
  ping은 ICMP(Internet Control Message Protocol) Echo Request/Reply를 사용.
  TCP/UDP와 달리 포트 번호가 없는 3계층(네트워크 계층) 프로토콜.

  ping이 성공하려면 경로상 모든 방화벽이 ICMP를 허용해야 함:
    · AWS 보안그룹  : 인바운드 ICMP 허용 (vpc-ping-test.yaml에서 설정 완료)
    · Azure NSG     : 인바운드 ICMP 허용 (nsg.bicep allow-icmp-from-aws 규칙)
    · GCP 방화벽    : 인바운드 icmp 허용 필요 (GCP 콘솔에서 별도 설정)
    · TGW 라우트    : ICMP는 IP 패킷이므로 라우팅만 되면 별도 설정 불필요

  ping은 count 없이 실행 → 연속 전송, Ctrl+C로 중단.
  패킷 드롭 발생 시 출력이 끊기거나 "Request timeout"이 찍히므로
  failover 순간의 패킷 손실 구간을 실시간으로 확인할 수 있음.

  ICMP가 차단된 환경에서는 vpn-failover-test.sh verify 단계의
  socket.create_connection(TCP) 방식으로 대체 가능.

── 사전 조건 ──────────────────────────────────────────────────────────
  bookflow-60-tgw 스택이 배포돼 있어야 함 (vpn-up 실행 후 사용).
  TGW에 Azure·GCP VPN attachment가 연결되고 BGP 경로가 수신된 상태여야
  ping이 실제로 성공함.
"""
import subprocess

from ..lib import Stack, log


_TEMPLATE = "60-network-cross-cloud/vpc-ping-test.yaml"
_STACK_NAME_SUFFIX = "vpc-ping-test"   # → bookflow-60-vpc-ping-test


def deploy() -> None:
    """테스트 VPC + TGW attachment + EC2를 CloudFormation으로 배포."""
    log.step("=== ping-test 배포 · VPC + TGW attachment + EC2(t3.micro) ===")

    Stack(tier="60", name=_STACK_NAME_SUFFIX, template=_TEMPLATE).deploy()

    # 배포 완료 후 CloudFormation Output에서 EC2 정보 조회
    outputs = Stack(tier="60", name=_STACK_NAME_SUFFIX, template="").outputs()
    ec2_id = outputs.get("Ec2InstanceId", "")
    ec2_public_ip = outputs.get("Ec2PublicIp", "")
    ec2_private_ip = outputs.get("Ec2PrivateIp", "")

    log.step("=== ping-test 배포 완료 ===")
    log.info(f"EC2 ID        : {ec2_id}")
    log.info(f"EC2 Public IP : {ec2_public_ip}")
    log.info(f"EC2 Private IP: {ec2_private_ip}")
    log.info("")
    log.info("SSH 접속:")
    log.info(f"  ssh -i <키페어.pem> ec2-user@{ec2_public_ip}")
    log.info("")
    # 172.16.2.4 = Azure services 서브넷 vm-ping-test VM private IP
    # ICMP Echo Request를 보내 TGW → VPN → Azure 경로가 뚫려 있는지 확인
    log.info("Azure ping (SSH 세션 내에서):")
    log.info("  ping 172.16.2.4     # Azure vm-ping-test private IP")
    # 192.168.10.2 = GCP VPC 내부 VM IP (GCP 쪽에 VM이 배포된 경우)
    log.info("GCP ping (SSH 세션 내에서):")
    log.info("  ping 192.168.10.2   # GCP VPC 내부 IP")


def ping(target: str = "", key_path: str = "") -> None:
    """SSH로 EC2에 접속해 Azure/GCP로 연속 ping(ICMP) 테스트 실행.

    count 없이 ping을 실행하므로 Ctrl+C로 중단할 때까지 계속 전송.
    failover 순간의 패킷 손실 구간을 실시간으로 확인하는 데 사용.

    출력 예시:
      64 bytes from 172.16.1.1: icmp_seq=1 ttl=253 time=3.2 ms
      64 bytes from 172.16.1.1: icmp_seq=2 ttl=253 time=3.1 ms
      Request timeout for icmp_seq 3   ← failover 전환 중 패킷 드롭 구간
      64 bytes from 172.16.1.1: icmp_seq=4 ttl=253 time=3.5 ms   ← Tunnel2 복귀

    Args:
        target  : 특정 IP를 지정하면 그 IP만 테스트. 생략 시 Azure·GCP 기본 IP 순서대로.
        key_path: EC2 키 페어 파일 경로 (예: ~/.ssh/bookflow.pem)
    """
    import boto3
    from ..lib.config import Config

    if not key_path:
        log.warn("key_path 필요: python bookflow.py ping --key-path ~/.ssh/bookflow.pem")
        return

    # CloudFormation Output에서 EC2 공인 IP 조회
    cfn = boto3.client("cloudformation", region_name=Config.REGION)
    try:
        outputs = {
            o["OutputKey"]: o["OutputValue"]
            for o in cfn.describe_stacks(
                StackName=f"{Config.STACK_PREFIX}-60-{_STACK_NAME_SUFFIX}"
            )["Stacks"][0].get("Outputs", [])
        }
    except Exception:
        log.warn("ping-test 스택 없음 — 먼저 배포 필요: python bookflow.py ping-test-up")
        return

    ec2_public_ip = outputs.get("Ec2PublicIp", "")
    if not ec2_public_ip:
        log.warn("EC2 Public IP 확인 불가")
        return

    targets = [target] if target else ["172.16.2.4", "192.168.10.2"]

    for ip in targets:
        log.info(f"ping {ip} 실행 중 (Ctrl+C로 중단)...")
        # SSH로 EC2에 접속해 ping 실행
        # count(-c) 없음 = 연속 전송 → failover 순간 패킷 드롭 실시간 확인 가능
        # StrictHostKeyChecking=no: 처음 접속 시 fingerprint 확인 프롬프트 건너뜀
        ssh_cmd = [
            "ssh",
            "-i", key_path,
            "-o", "StrictHostKeyChecking=no",
            f"ec2-user@{ec2_public_ip}",
            f"ping {ip}",
        ]
        try:
            # check=False: Ctrl+C로 중단 시 non-zero exit code를 에러로 처리하지 않음
            subprocess.run(ssh_cmd, check=False)
        except KeyboardInterrupt:
            log.info("ping 중단")
            break


def destroy() -> None:
    """테스트 VPC + EC2 스택 삭제."""
    log.step("=== ping-test destroy ===")
    Stack(tier="60", name=_STACK_NAME_SUFFIX, template="").destroy()
    log.step("=== ping-test destroy 완료 ===")
