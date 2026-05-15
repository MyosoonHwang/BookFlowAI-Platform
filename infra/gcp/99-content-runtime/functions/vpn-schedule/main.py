import os
import functions_framework
import google.auth
import google.auth.transport.requests
import requests as http_requests

PROJECT = "project-8ab6bf05-54d2-4f5d-b8d"
REGION  = "asia-northeast1"

TUNNELS = {
    "bookflow-aws-tunnel-tunnel0": {
        "vpnGateway":                   f"projects/{PROJECT}/regions/{REGION}/vpnGateways/bookflow-aws-ha-vpn",
        "vpnGatewayInterface":          0,
        "peerExternalGateway":          f"projects/{PROJECT}/global/externalVpnGateways/bookflow-aws-tgw-external-gw",
        "peerExternalGatewayInterface": 0,
        "router":                       f"projects/{PROJECT}/regions/{REGION}/routers/bookflow-aws-cr",
        "ikeVersion":                   2,
        "sharedSecretEnv":              "VPN_SECRET_T0",
    },
    "bookflow-aws-tunnel-tunnel1": {
        "vpnGateway":                   f"projects/{PROJECT}/regions/{REGION}/vpnGateways/bookflow-aws-ha-vpn",
        "vpnGatewayInterface":          1,
        "peerExternalGateway":          f"projects/{PROJECT}/global/externalVpnGateways/bookflow-aws-tgw-external-gw",
        "peerExternalGatewayInterface": 1,
        "router":                       f"projects/{PROJECT}/regions/{REGION}/routers/bookflow-aws-cr",
        "ikeVersion":                   2,
        "sharedSecretEnv":              "VPN_SECRET_T1",
    },
}

def _token():
    creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/compute"])
    creds.refresh(google.auth.transport.requests.Request())
    return creds.token

@functions_framework.http
def handler(request):
    action = request.args.get("action", "")
    if action == "up":
        return _up()
    if action == "down":
        return _down()
    return ({"error": "action must be 'up' or 'down'"}, 400)

def _up():
    hdrs = {"Authorization": f"Bearer {_token()}", "Content-Type": "application/json"}
    base = f"https://compute.googleapis.com/compute/v1/projects/{PROJECT}/regions/{REGION}/vpnTunnels"
    results = []
    for name, cfg in TUNNELS.items():
        body = {
            "name":                           name,
            "vpnGateway":                     cfg["vpnGateway"],
            "vpnGatewayInterface":            cfg["vpnGatewayInterface"],
            "peerExternalGateway":            cfg["peerExternalGateway"],
            "peerExternalGatewayInterface":   cfg["peerExternalGatewayInterface"],
            "router":                         cfg["router"],
            "ikeVersion":                     cfg["ikeVersion"],
            "sharedSecret":                   os.environ[cfg["sharedSecretEnv"]],
        }
        r = http_requests.post(base, headers=hdrs, json=body)
        results.append(f"{name}: {r.status_code}")
    return {"action": "up", "results": results}, 200

def _down():
    hdrs = {"Authorization": f"Bearer {_token()}"}
    base = f"https://compute.googleapis.com/compute/v1/projects/{PROJECT}/regions/{REGION}/vpnTunnels"
    results = []
    for name in TUNNELS:
        r = http_requests.delete(f"{base}/{name}", headers=hdrs)
        results.append(f"{name}: {r.status_code}")
    return {"action": "down", "results": results}, 200
