################################################################################
# Karpenter node IAM role and instance profile
################################################################################

data "aws_iam_policy_document" "karpenter_node_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "karpenter_node" {
  name               = "${local.cluster_name}-karpenter-node"
  assume_role_policy = data.aws_iam_policy_document.karpenter_node_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${local.cluster_name}-karpenter-node"
  role = aws_iam_role.karpenter_node.name
  tags = local.common_tags
}

resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = local.cluster_name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
  tags          = local.common_tags
}

################################################################################
# Interruption handling queue
################################################################################

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${local.cluster_name}-karpenter-interruption"
  message_retention_seconds = var.sqs_message_retention_seconds
  sqs_managed_sse_enabled   = true
  tags                      = local.common_tags
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowEventBridgeSendMessage"
      Effect   = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.karpenter_interruption.arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "spot_interruptions" {
  name          = "${local.cluster_name}-spot-interruptions"
  description   = "Spot interruption events for Karpenter"
  event_pattern = jsonencode({ source = ["aws.ec2"], detail-type = ["EC2 Spot Instance Interruption Warning"] })
}
resource "aws_cloudwatch_event_target" "spot_interruptions" {
  rule      = aws_cloudwatch_event_rule.spot_interruptions.name
  target_id = "karpenter"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "rebalance" {
  name          = "${local.cluster_name}-rebalance"
  description   = "EC2 rebalance recommendations for Karpenter"
  event_pattern = jsonencode({ source = ["aws.ec2"], detail-type = ["EC2 Instance Rebalance Recommendation"] })
}
resource "aws_cloudwatch_event_target" "rebalance" {
  rule      = aws_cloudwatch_event_rule.rebalance.name
  target_id = "karpenter"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name          = "${local.cluster_name}-instance-state-change"
  description   = "EC2 instance state change events for Karpenter"
  event_pattern = jsonencode({ source = ["aws.ec2"], detail-type = ["EC2 Instance State-change Notification"] })
}
resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule      = aws_cloudwatch_event_rule.instance_state_change.name
  target_id = "karpenter"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

################################################################################
# Karpenter controller IAM role (IRSA)
################################################################################

data "aws_iam_policy_document" "karpenter_controller_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${local.cluster_name}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_policy" "karpenter_controller" {
  name        = "${local.cluster_name}-karpenter-controller"
  description = "IAM policy for Karpenter controller"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EC2Write"
        Effect   = "Allow"
        Action   = ["ec2:CreateFleet","ec2:RunInstances","ec2:CreateLaunchTemplate","ec2:CreateTags","ec2:DeleteLaunchTemplate","ec2:TerminateInstances"]
        Resource = "*"
      },
      {
        Sid      = "EC2Read"
        Effect   = "Allow"
        Action   = ["ec2:DescribeAvailabilityZones","ec2:DescribeImages","ec2:DescribeInstanceTypeOfferings","ec2:DescribeInstanceTypes","ec2:DescribeInstances","ec2:DescribeLaunchTemplates","ec2:DescribeSecurityGroups","ec2:DescribeSpotPriceHistory","ec2:DescribeSubnets"]
        Resource = "*"
      },
      {
        Sid      = "PricingRead"
        Effect   = "Allow"
        Action   = ["pricing:GetProducts"]
        Resource = "*"
      },
      {
        Sid      = "PassNodeRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.karpenter_node.arn
      },
      {
        Sid      = "ManageInstanceProfiles"
        Effect   = "Allow"
        Action   = ["iam:AddRoleToInstanceProfile","iam:CreateInstanceProfile","iam:DeleteInstanceProfile","iam:GetInstanceProfile","iam:RemoveRoleFromInstanceProfile","iam:TagInstanceProfile"]
        Resource = "*"
      },
      {
        Sid      = "EKSRead"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = local.cluster_arn
      },
      {
        Sid      = "SSMRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:*:*:parameter/aws/service/*"
      },
      {
        Sid      = "SQSRead"
        Effect   = "Allow"
        Action   = ["sqs:DeleteMessage","sqs:GetQueueAttributes","sqs:GetQueueUrl","sqs:ReceiveMessage"]
        Resource = aws_sqs_queue.karpenter_interruption.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

################################################################################
# Helm releases
################################################################################

data "aws_ecrpublic_authorization_token" "karpenter" {
  provider = aws.us_east_1
}

resource "helm_release" "karpenter_crd" {
  name                = "karpenter-crd"
  namespace           = "kube-system"
  create_namespace    = false
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter-crd"
  version             = var.karpenter_version
  repository_username = data.aws_ecrpublic_authorization_token.karpenter.user_name
  repository_password = data.aws_ecrpublic_authorization_token.karpenter.password
}

resource "helm_release" "karpenter" {
  name                = "karpenter"
  namespace           = "kube-system"
  create_namespace    = false
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter"
  version             = var.karpenter_version
  repository_username = data.aws_ecrpublic_authorization_token.karpenter.user_name
  repository_password = data.aws_ecrpublic_authorization_token.karpenter.password

  values = [yamlencode({
    serviceAccount = {
      create = true
      name   = "karpenter"
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller.arn
      }
    }
    settings = {
      clusterName       = local.cluster_name
      interruptionQueue = aws_sqs_queue.karpenter_interruption.name
    }
  })]

  depends_on = [
    helm_release.karpenter_crd,
    aws_iam_role_policy_attachment.karpenter_controller,
    aws_sqs_queue_policy.karpenter_interruption,
  ]
}

################################################################################
# EC2NodeClass + NodePools
# Uses kubectl_manifest (gavinbunney/kubectl) — skips plan-time CRD validation.
# amiSelectorTerms replaces the deprecated amiFamily field in Karpenter v1.
################################################################################

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      # amiSelectorTerms replaces amiFamily in Karpenter v1.
      # The SSM alias always resolves to the latest EKS-optimized AL2023 AMI
      # for the cluster's Kubernetes version.
      amiSelectorTerms:
        - alias: al2023@latest
      role: ${aws_iam_role.karpenter_node.name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${local.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${local.cluster_name}
      tags:
        karpenter.sh/discovery: ${local.cluster_name}
        Name: ${local.cluster_name}-karpenter
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: ${var.node_volume_size}Gi
            volumeType: gp3
            deleteOnTermination: true
  YAML

  depends_on = [
    helm_release.karpenter,
    aws_eks_access_entry.karpenter_node,
  ]
}

resource "kubectl_manifest" "karpenter_node_pool_amd64" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: amd64
    spec:
      template:
        metadata:
          labels:
            workload-arch: amd64
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          taints:
            - key: workload-arch
              value: amd64
              effect: NoSchedule
          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            - key: kubernetes.io/os
              operator: In
              values: ["linux"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["c", "m", "r"]
            - key: karpenter.k8s.aws/instance-generation
              operator: Gt
              values: ["5"]
          expireAfter: 720h
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
      limits:
        cpu: "${var.nodepool_cpu_limit}"
        memory: ${var.nodepool_memory_limit}
      # No weight — arm64 pool (weight: 10) is preferred when both archs
      # could satisfy the workload request.
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}

resource "kubectl_manifest" "karpenter_node_pool_arm64" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: arm64
    spec:
      template:
        metadata:
          labels:
            workload-arch: arm64
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          taints:
            - key: workload-arch
              value: arm64
              effect: NoSchedule
          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["arm64"]
            - key: kubernetes.io/os
              operator: In
              values: ["linux"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["c", "m", "r"]
            - key: karpenter.k8s.aws/instance-generation
              operator: Gt
              values: ["6"]
          expireAfter: 720h
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
      limits:
        cpu: "${var.nodepool_cpu_limit}"
        memory: ${var.nodepool_memory_limit}
      # weight: 10 — Karpenter prefers Graviton over x86 when both could
      # satisfy the workload, giving better price/performance.
      weight: 10
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}

################################################################################
# PodDisruptionBudget for bootstrap node group
################################################################################

resource "kubectl_manifest" "bootstrap_pdb" {
  yaml_body = <<-YAML
    apiVersion: policy/v1
    kind: PodDisruptionBudget
    metadata:
      name: bootstrap-pdb
      namespace: kube-system
    spec:
      minAvailable: 1
      selector:
        matchLabels:
          role: bootstrap
  YAML
}
