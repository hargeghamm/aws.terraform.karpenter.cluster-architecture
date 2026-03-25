# Innovate Inc — Cloud Architecture Design

## Overview

This document describes the recommended AWS cloud infrastructure for Innovate Inc., a startup building a Python/Flask REST API backend, React SPA frontend, and PostgreSQL database. The design prioritises security, scalability, cost-efficiency, and CI/CD readiness.

---

## Cloud Environment Structure

### Recommended: 3-Account AWS Organisation

| Account | Purpose |
|---|---|
| **Management** | Billing, AWS SSO/IAM Identity Center, SCPs, audit logging only. No workloads. |
| **Non-Production** | Dev and staging environments, feature branch deployments, load testing. |
| **Production** | Live customer traffic. Strict IAM, change-control, and alerting. |

**Justification:**
- Blast-radius containment — a misconfiguration in non-prod cannot affect production.
- Independent billing visibility per environment.
- Enables strict Service Control Policies (SCPs) on production (e.g. deny resource deletion without MFA).
- Follows AWS Well-Architected and Landing Zone best practices.

---

## Network Design

### VPC Architecture (per account)

```
┌─────────────────────────────── VPC (10.0.0.0/16) ───────────────────────────────┐
│                                                                                   │
│  ┌──────────────── Public Subnets (x3 AZs) ──────────────────┐                  │
│  │  ALB (HTTPS 443)     NAT Gateway     Bastion (optional)    │                  │
│  └────────────────────────────────────────────────────────────┘                  │
│                              │                                                    │
│  ┌──────────────── Private Subnets (x3 AZs) ─────────────────┐                  │
│  │  EKS Worker Nodes (Flask API pods)                         │                  │
│  │  Internal ALB / Service mesh                               │                  │
│  └────────────────────────────────────────────────────────────┘                  │
│                              │                                                    │
│  ┌──────────────── Isolated Subnets (x3 AZs) ────────────────┐                  │
│  │  RDS PostgreSQL (Multi-AZ)    ElastiCache (optional)       │                  │
│  └────────────────────────────────────────────────────────────┘                  │
└───────────────────────────────────────────────────────────────────────────────── ┘
```

### Network Security

- **AWS WAF + Shield Standard** in front of the public ALB — blocks OWASP top-10, rate limits.
- **Security Groups** follow least-privilege: ALB SG → EKS node SG → RDS SG (only port 5432 from node SG).
- **NACLs** provide a secondary stateless layer.
- **VPC Flow Logs** → S3 + Athena for audit and incident response.
- **AWS PrivateLink / VPC Endpoints** for S3, ECR, SQS, and Secrets Manager so traffic never leaves the AWS backbone.
- No SSH exposed publicly; use **AWS Systems Manager Session Manager** for node access.

---

## Compute Platform — Amazon EKS

### Cluster Setup

- **Amazon EKS** (latest version) deployed across 3 AZs in private subnets.
- **EKS Managed Node Groups** with Karpenter for autoscaling (same pattern as the technical task).
- **Node groups:**
  - `system` — On-Demand, t3/m6i, runs CoreDNS, monitoring agents, Karpenter controller.
  - `app` — Spot + On-Demand via Karpenter, scales Flask API pods.

### Container & Deployment Strategy

- **Amazon ECR** (private) stores all Docker images; image scanning enabled.
- Docker images built with **multi-stage Dockerfiles** to minimise image size.
- Deployments use **Kubernetes Deployments** with `RollingUpdate` strategy and `PodDisruptionBudgets`.
- **Horizontal Pod Autoscaler (HPA)** scales Flask pods based on CPU/memory.
- React SPA is a static build served via **Amazon CloudFront + S3** — no Kubernetes needed for the frontend.

### Resource Allocation

- Each Flask pod: `requests: cpu=250m, memory=256Mi` / `limits: cpu=500m, memory=512Mi`.
- Karpenter provisions nodes just-in-time; consolidation policy removes underutilised nodes.

---

## Database — Amazon RDS for PostgreSQL

### Service Choice

**Amazon RDS for PostgreSQL** (latest stable engine version) in **Multi-AZ** configuration.

**Justification over alternatives:**
- Fully managed: patching, backups, failover handled by AWS.
- Multi-AZ provides synchronous standby replica — automatic failover in ~60s.
- Aurora PostgreSQL is more expensive and complexity is unnecessary at initial scale.

### Backup & HA

| Concern | Solution |
|---|---|
| Automated backups | 7-day retention, daily snapshots to S3 |
| Point-in-time recovery | Enabled (5-minute RPO) |
| High availability | Multi-AZ standby replica (synchronous) |
| Disaster recovery | Weekly manual snapshot copied to a second region |
| Credentials | Stored in **AWS Secrets Manager**; rotated automatically every 30 days |
| Encryption | Storage encrypted with KMS CMK; in-transit via SSL enforced |

---

## CI/CD Pipeline

```
 Developer → GitHub PR → GitHub Actions
                              │
              ┌───────────────┼────────────────┐
              ▼               ▼                ▼
          Lint/Test      Build Docker      Security scan
                         image                (Trivy)
                              │
                    Push to Amazon ECR
                              │
              ┌───────────────┴────────────────┐
              ▼                                ▼
    Deploy to Non-Prod EKS            Manual approval gate
    (auto on merge to main)                    │
                                               ▼
                                    Deploy to Prod EKS
```

- **GitHub Actions** workflows for build, test, scan, and deploy.
- **Trivy** image vulnerability scanning before push to ECR.
- **Helm charts** or **Kustomize** manage Kubernetes manifests.
- Environment-specific values via separate `values-nonprod.yaml` / `values-prod.yaml`.
- Prod deploy requires manual approval (`environment: production` protection rule in GitHub).

---

## High-Level Architecture Diagram

```
                         ┌─────────────┐
                         │   Users     │
                         └──────┬──────┘
                                │ HTTPS
                         ┌──────▼──────┐
                         │  CloudFront │◄── React SPA (S3)
                         └──────┬──────┘
                                │ API requests
                    ┌───────────▼───────────┐
                    │   AWS WAF + Shield    │
                    └───────────┬───────────┘
                                │
                    ┌───────────▼───────────┐
                    │  Application LB (ALB) │  (public subnet)
                    └───────────┬───────────┘
                                │
          ┌─────────────────────▼──────────────────────┐
          │              Amazon EKS Cluster             │
          │           (private subnets, 3 AZs)          │
          │                                             │
          │   ┌─────────────┐   ┌────────────────────┐ │
          │   │ System pods │   │  Flask API pods    │ │
          │   │ (CoreDNS,   │   │  (Deployment + HPA)│ │
          │   │  Karpenter) │   └─────────┬──────────┘ │
          │   └─────────────┘             │            │
          └──────────────────────────────-┼────────────┘
                                          │
               ┌──────────────────────────▼───────────────────┐
               │           Isolated Subnets                    │
               │  ┌─────────────────────────────────────────┐  │
               │  │  RDS PostgreSQL Multi-AZ                │  │
               │  │  Primary (AZ-a) ↔ Standby (AZ-b)       │  │
               │  └─────────────────────────────────────────┘  │
               └───────────────────────────────────────────────┘

  Supporting services (all via VPC Endpoints):
  ┌──────────┐  ┌──────────┐  ┌─────────────────┐  ┌──────────┐
  │  Amazon  │  │  AWS     │  │  AWS Secrets    │  │  Amazon  │
  │   ECR    │  │  S3      │  │  Manager        │  │CloudWatch│
  └──────────┘  └──────────┘  └─────────────────┘  └──────────┘

  CI/CD:
  GitHub → GitHub Actions → ECR → EKS (non-prod auto / prod manual gate)
```

---

## Security Summary

- All sensitive data encrypted at rest (KMS) and in transit (TLS).
- Secrets managed via AWS Secrets Manager with automatic rotation.
- IAM roles follow least-privilege; no long-lived access keys.
- Pod-level IAM via **IRSA** (IAM Roles for Service Accounts).
- Container images scanned for CVEs before deployment (Trivy).
- AWS WAF protects the public API endpoint.
- VPC Flow Logs + CloudTrail + CloudWatch Alarms for observability and audit.
