output "karpenter_node_role_arn" {
  description = "IAM role ARN assumed by Karpenter-provisioned nodes"
  value       = aws_iam_role.karpenter_node.arn
}

output "karpenter_controller_role_arn" {
  description = "IAM role ARN used by the Karpenter controller (IRSA)"
  value       = aws_iam_role.karpenter_controller.arn
}

output "karpenter_interruption_queue_name" {
  description = "SQS queue name for spot-interruption handling"
  value       = aws_sqs_queue.karpenter_interruption.name
}

output "karpenter_interruption_queue_arn" {
  description = "SQS queue ARN for spot-interruption handling"
  value       = aws_sqs_queue.karpenter_interruption.arn
}
