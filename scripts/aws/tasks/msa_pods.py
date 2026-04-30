"""task-msa-pods · EKS Cluster + Node Group + Addons + IRSA + endpoints + peering."""
from ..lib import Stack, log


def deploy() -> None:
    log.step("=== task-msa-pods · EKS + endpoints + peering ===")

    if not Stack(tier="10", name="vpc-bookflow-ai", template="").exists():
        log.err("vpc-bookflow-ai  · base-up "); raise SystemExit(1)

    Stack(tier="10", name="endpoints-bookflow-ai",
          template="10-network-core/endpoints/endpoints-bookflow-ai.yaml").deploy()
    Stack(tier="10", name="peering-bookflow-ai-data",
          template="10-network-core/peering/bookflow-ai-data.yaml").deploy()
    Stack(tier="10", name="peering-bookflow-ai-egress",
          template="10-network-core/peering/bookflow-ai-egress.yaml").deploy()

    Stack(tier="30", name="eks-cluster",
          template="30-compute-cluster/eks-cluster.yaml").deploy()
    Stack(tier="30", name="eks-alb-controller-irsa",
          template="30-compute-cluster/eks-alb-controller-irsa.yaml").deploy()
    Stack(tier="30", name="eks-eso-irsa",
          template="30-compute-cluster/eks-eso-irsa.yaml").deploy()

    Stack(tier="40", name="eks-nodegroup",
          template="40-compute-runtime/eks-nodegroup.yaml").deploy()
    Stack(tier="40", name="eks-addons",
          template="40-compute-runtime/eks-addons.yaml").deploy()

    log.step("=== task-msa-pods  ===")
    log.info("kubeconfig: aws eks update-kubeconfig --name bookflow-eks --region ap-northeast-1")


def destroy() -> None:
    log.step("=== task-msa-pods-down ===")
    Stack(tier="40", name="eks-addons", template="").destroy()
    Stack(tier="40", name="eks-nodegroup", template="").destroy()
    Stack(tier="30", name="eks-eso-irsa", template="").destroy()
    Stack(tier="30", name="eks-alb-controller-irsa", template="").destroy()
    Stack(tier="30", name="eks-cluster", template="").destroy()
    Stack(tier="10", name="peering-bookflow-ai-egress", template="").destroy()
    Stack(tier="10", name="peering-bookflow-ai-data", template="").destroy()
    Stack(tier="10", name="endpoints-bookflow-ai", template="").destroy()
    log.step("=== task-msa-pods-down  ===")
