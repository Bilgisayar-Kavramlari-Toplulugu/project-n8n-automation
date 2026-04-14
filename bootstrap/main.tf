variable "github_repo" {
  description = "GitHub repository scope. Repo hazir degilse gecici olarak 'org/*' kullanabilirsiniz; repo olusunca 'org/repo' seviyesine daraltin."
  type        = string
  default     = "Bilgisayar-Kavramlari-Toplulugu/*" # Burayı kendi reponuzla güncelleyin!
}

variable "github_default_branch" {
  description = "Terraform deploy workflow'lerinin çalıştığı varsayılan branch"
  type        = string
  default     = "main"
}

locals {
  github_oidc_subjects = [
    "repo:${var.github_repo}:pull_request",
    "repo:${var.github_repo}:ref:refs/heads/${var.github_default_branch}",
  ]
}

provider "aws" {
  region = "eu-central-1"
}

# 1. State dosyalarını saklayacak S3 Bucket
resource "aws_s3_bucket" "terraform_state" {
  bucket = "n8n-terraform-state-2026"

  # lifecycle {
  #   prevent_destroy = true
  # }
}

resource "aws_s3_bucket_versioning" "state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 2. State kilitleme (Locking) için DynamoDB Tablosu
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# 3. GitHub OIDC Identity Provider
# GitHub'ın AWS'e güvenli bağlanmasını sağlar
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # GitHub's CA thumbprint
}

# 4. Terraform IAM Role (GitHub Actions tarafından assume edilir)
resource "aws_iam_role" "github_terraform_role" {
  name = "GitHubTerraformExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.github_oidc_subjects
          }
        }
      }
    ]
  })
}

# Role için bu stack'in ihtiyaç duyduğu minimum yetkiler
resource "aws_iam_role_policy" "terraform_execution" {
  name = "TerraformExecutionPolicy"
  role = aws_iam_role.github_terraform_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateBucket"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:ListBucket",
        ]
        Resource = aws_s3_bucket.terraform_state.arn
      },
      {
        Sid    = "TerraformStateObjects"
        Effect = "Allow"
        Action = [
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = "${aws_s3_bucket.terraform_state.arn}/*"
      },
      {
        Sid    = "TerraformLockTable"
        Effect = "Allow"
        Action = [
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
        ]
        Resource = aws_dynamodb_table.terraform_locks.arn
      },
      {
        Sid    = "Ec2Describe"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
        ]
        Resource = "*"
      },
      {
        Sid    = "Ec2ManageInfrastructure"
        Effect = "Allow"
        Action = [
          "ec2:AssociateRouteTable",
          "ec2:AttachInternetGateway",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CancelSpotInstanceRequests",
          "ec2:CreateInternetGateway",
          "ec2:CreateRoute",
          "ec2:CreateRouteTable",
          "ec2:CreateSecurityGroup",
          "ec2:CreateSubnet",
          "ec2:CreateTags",
          "ec2:CreateVpc",
          "ec2:DeleteInternetGateway",
          "ec2:DeleteKeyPair",
          "ec2:DeleteRoute",
          "ec2:DeleteRouteTable",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteSubnet",
          "ec2:DeleteTags",
          "ec2:DeleteVpc",
          "ec2:DetachInternetGateway",
          "ec2:DisassociateRouteTable",
          "ec2:ImportKeyPair",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifySubnetAttribute",
          "ec2:ModifyVpcAttribute",
          "ec2:RebootInstances",
          "ec2:ReplaceRoute",
          "ec2:RequestSpotInstances",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RunInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
        ]
        Resource = "*"
      },
    ]
  })
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.terraform_locks.name
}

output "github_role_arn" {
  value       = aws_iam_role.github_terraform_role.arn
  description = "GitHub Actions'a ekleyeceğiniz ROLE_ARN"
}
