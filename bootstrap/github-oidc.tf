# GitHub OIDC Provider for AWS Authentication
# This allows GitHub Actions to assume AWS roles without static credentials

# GitHub's OIDC provider thumbprint
# This rarely changes, but can be verified at:
# https://github.blog/changelog/2023-06-27-github-actions-update-on-oidc-integration-with-aws/

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = {
    Name = "github-actions-oidc"
  }
}

# IAM Role for GitHub Actions - Terraform
resource "aws_iam_role" "github_actions_terraform" {
  name = "${var.project_name}-github-terraform"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Restrict to specific repos
            "token.actions.githubusercontent.com:sub" = [
              "repo:https://github.com/kalyan-p-2026/devops-infra:*",
              "repo:https://github.com/kalyan-p-2026/devops-app*",
              "repo:https://github.com/kalyan-p-2026/devops-gitops:*"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-github-terraform"
  }
}

# Policy for Terraform operations
resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "terraform-permissions"
  role = aws_iam_role.github_actions_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
      {
        Sid    = "TerraformLockAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.terraform_lock.arn
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.terraform_state.arn
      },
      {
        Sid    = "EC2VPCFullAccess"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "elasticloadbalancing:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "EKSFullAccess"
        Effect = "Allow"
        Action = [
          "eks:*",
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:PassRole",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListInstanceProfilesForRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53Access"
        Effect = "Allow"
        Action = [
          "route53:*",
          "acm:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Output the role ARN for GitHub Actions
output "github_actions_role_arn" {
  description = "ARN of IAM role for GitHub Actions"
  value       = aws_iam_role.github_actions_terraform.arn
}
