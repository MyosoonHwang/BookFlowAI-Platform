# functions/sync-secret/__init__.py
# Key Vault SecretNewVersionCreated 이벤트 수신 후 AWS Secrets Manager 동기화
# VPN 연결 전: AWS 호출 부분은 로그만 출력
# VPN 연결 후: AWS_API_GATEWAY_URL 앱 설정 값으로 실제 호출 활성화

import logging
import json
import os
import azure.functions as func
from azure.identity import ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient

def main(event: func.EventGridEvent) -> None:
    logging.info("Event Grid 이벤트 수신")

    try:
        event_data = event.get_json()
        secret_name = event_data.get("ObjectName", "")
        secret_version = event_data.get("Version", "")
        vault_name = event_data.get("VaultName", "")

        logging.info(f"시크릿 변경 감지 - 이름: {secret_name}, 버전: {secret_version}")

        # 관리 ID 로 Key Vault 접근
        key_vault_uri = os.environ.get("KEY_VAULT_URI")
        credential = ManagedIdentityCredential(
            client_id=os.environ.get("AZURE_CLIENT_ID")
        )
        kv_client = SecretClient(vault_url=key_vault_uri, credential=credential)

        # 시크릿 값 조회
        secret = kv_client.get_secret(secret_name)
        secret_value = secret.value
        logging.info(f"시크릿 조회 성공: {secret_name}")

        # AWS API Gateway URL 확인
        aws_api_url = os.environ.get("AWS_API_GATEWAY_URL", "")

        if aws_api_url == "PLACEHOLDER-VPN-CONNECTED-LATER" or not aws_api_url:
            # VPN 연결 전 — AWS 호출 건너뜀
            logging.warning(
                f"[VPN 연결 전] AWS Secrets Manager 동기화 건너뜀 - "
                f"시크릿: {secret_name} - "
                f"VPN 연결 후 aws-api-gateway-url 업데이트 필요"
            )
            return

        # VPN 연결 후 아래 코드 활성화
        import requests

        payload = {
            "secret_name": f"bookflow/azure/{secret_name}",
            "secret_value": secret_value
        }

        response = requests.post(
            aws_api_url,
            json=payload,
            timeout=10
        )

        if response.status_code == 200:
            logging.info(f"AWS Secrets Manager 동기화 성공: {secret_name}")
        else:
            logging.error(
                f"AWS 동기화 실패 - 상태코드: {response.status_code} - "
                f"응답: {response.text}"
            )
            raise Exception(f"AWS API 호출 실패: {response.status_code}")

    except Exception as e:
        logging.error(f"처리 실패: {str(e)}")
        raise
