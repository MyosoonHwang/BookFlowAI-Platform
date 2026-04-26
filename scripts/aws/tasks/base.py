"""base-up / base-down · 매일 아침 base 인프라 + 매일 저녁 전체 destroy."""
from ..lib import Stack, log

TIER10 = [
    ("vpc-bookflow-ai",  "10-network-core/vpc-bookflow-ai.yaml"),
    ("vpc-sales-data",   "10-network-core/vpc-sales-data.yaml"),
    ("vpc-egress",       "10-network-core/vpc-egress.yaml"),
    ("vpc-data",         "10-network-core/vpc-data.yaml"),
    ("vpc-ansible",      "10-network-core/vpc-ansible.yaml"),
    ("customer-gateway", "10-network-core/customer-gateway.yaml"),
    ("route53",          "10-network-core/route53.yaml"),
]

TIER30 = [
    ("ecs-cluster",  "30-compute-cluster/ecs-cluster.yaml"),
    ("ansible-node", "30-compute-cluster/ansible-node.yaml"),
]


def deploy() -> None:
    log.step("=== base-up · Tier 10 + Tier 30 base ===")
    for name, template in TIER10:
        Stack(tier="10", name=name, template=template).deploy()
    for name, template in TIER30:
        Stack(tier="30", name=name, template=template).deploy()
    log.step("=== base-up 완료 (Tier 00 영구 + Tier 10/30 base) ===")


def destroy() -> None:
    """매일 저녁 18:00 · Tier 10-60 + 99 전부 destroy (Tier 00 영구 유지)."""
    log.step("=== base-down · Tier 10-99 전체 destroy ===")

    DOWN_ORDER = {
        "99": ["step-functions", "glue-catalog", "lambdas"],
        "60": ["client-vpn", "vpn-site-to-site", "tgw"],
        "50": ["waf", "alb-external", "nat-gateway"],
        "40": ["ecs-online-sim", "ecs-offline-sim", "ecs-inventory-api",
               "publisher-asg", "eks-addons", "eks-nodegroup"],
        "30": ["eks-eso-irsa", "eks-alb-controller-irsa", "eks-cluster",
               "ansible-node", "ecs-cluster"],
        "20": ["kinesis", "redis", "rds"],
        "10": [
            "peering-bookflow-ai-data", "peering-bookflow-ai-egress",
            "peering-egress-data", "peering-sales-data-egress", "peering-ansible-data",
            "endpoints-bookflow-ai", "endpoints-sales-data", "endpoints-ansible",
            "route53", "customer-gateway",
            "vpc-bookflow-ai", "vpc-sales-data", "vpc-egress", "vpc-data", "vpc-ansible",
        ],
    }

    for tier, names in DOWN_ORDER.items():
        for name in names:
            Stack(tier=tier, name=name, template="").destroy()

    log.step("=== base-down 완료 · 비용 $0 (Tier 00 제외) ===")
