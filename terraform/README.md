# EKS + Karpenter POC

This Terraform setup is split into **two independent root modules** to avoid the provider chicken-and-egg problem (Helm/Kubernetes providers need the cluster to exist before they can initialise):

```
terraform/
├── 01-cluster/      ← VPC + EKS cluster (run first)
├── 02-karpenter/    ← Karpenter IAM + Helm + NodePools (run second)
└── scripts/
    └── bootstrap-backend.sh
```

## What each module creates

### 01-cluster
- Dedicated VPC (3 AZs, public + private subnets, NAT Gateway)
- Amazon EKS cluster (default: **1.35**)
- Bootstrap managed node group (On-Demand, hosts CoreDNS + Karpenter)
- All outputs written to S3 remote state for `02-karpenter` to consume

### 02-karpenter
- Karpenter node IAM role + instance profile
- Karpenter controller IAM role (IRSA)
- SQS queue + EventBridge rules for Spot interruption handling
- Karpenter Helm release (default: **1.9.0**)
- `EC2NodeClass` (AL2023, gp3 50 GiB)
- `NodePool/amd64` — x86_64, Spot + On-Demand, gen > 5
- `NodePool/arm64` — Graviton, Spot + On-Demand, gen > 6, `weight: 10` (preferred)
- `PodDisruptionBudget` for the bootstrap node group
- Example manifests in `manifests/`

---

## Versions

| Component  | Default  |
|------------|----------|
| Kubernetes | `1.35`   |
| Karpenter  | `1.9.0`  |
| Terraform  | `>= 1.6` |

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- AWS credentials exported in your shell

```bash
export AWS_PROFILE=my-profile
```

---

## Step 1 — Bootstrap the S3 backend (once per environment)

```bash
chmod +x scripts/bootstrap-backend.sh
./scripts/bootstrap-backend.sh
# Custom bucket: BUCKET_NAME=my-tf-state-bucket ./scripts/bootstrap-backend.sh
```

Then replace `REPLACE_ME_tf-state-startup-eks-poc` with your actual bucket name in:
- `01-cluster/backend.tf`
- `02-karpenter/backend.tf`
- `02-karpenter/terraform.tfvars` (`state_bucket`)

---

## Step 2 — Deploy the cluster

```bash
cd terraform/01-cluster
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Configure kubectl once apply completes:

```bash
aws eks update-kubeconfig \
  --region $(terraform output -raw region) \
  --name $(terraform output -raw cluster_name)

kubectl get nodes
```

---

## Step 3 — Deploy Karpenter

```bash
cd ../02-karpenter
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Verify:

```bash
kubectl get nodepools
kubectl get ec2nodeclasses
```

---

## Step 4 — Run workloads

```bash
# x86
kubectl apply -f manifests/example-amd64-deployment.yaml

# Graviton (arm64)
kubectl apply -f manifests/example-arm64-deployment.yaml

# Watch Karpenter provision nodes
kubectl get nodes -w -L kubernetes.io/arch,karpenter.sh/capacity-type
```

**x86 manifest** uses `nodeSelector: kubernetes.io/arch: amd64` + toleration for `workload-arch=amd64:NoSchedule`.

**arm64 manifest** uses `nodeSelector: kubernetes.io/arch: arm64` + toleration for `workload-arch=arm64:NoSchedule`.

> `nginx:stable-alpine` is a multi-arch image — the correct binary is pulled automatically per node architecture.

---

## Architecture overview

The bootstrap node group hosts only system pods. Application capacity is managed entirely by Karpenter:

- `NodePool/arm64` has `weight: 10` — Karpenter prefers Graviton when either arch could satisfy the workload (better price/performance)
- Both pools carry a `workload-arch` taint so only explicitly opted-in pods land on them
- Spot interruptions are handled gracefully via the SQS + EventBridge pipeline

---

## Destroy (reverse order)

```bash
# Remove Karpenter-managed nodes first
kubectl delete nodes -l karpenter.sh/initialized=true

cd terraform/02-karpenter && terraform destroy
cd ../01-cluster && terraform destroy
```

---

## Notes

- POC setup — `single_nat_gateway = true` reduces cost. Set to `false` for production.
- S3 bucket names are globally unique — use a project-specific prefix.
- State locking via DynamoDB prevents concurrent `terraform apply` runs from corrupting state.
