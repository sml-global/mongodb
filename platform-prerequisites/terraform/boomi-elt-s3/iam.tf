# Production Environment: IAM Role with cross-account assume permissions
resource "aws_iam_role" "prod_admin" {
  count = local.is_prod ? 1 : 0
  name  = "sml-elt-admin-prod"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"  # Boomi atom runs on EC2
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  max_session_duration = 3600  # 1 hour

  tags = {
    Name = "Boomi ELT Admin (Production)"
  }
}

# Production role policy: Full access to prod bucket + AssumeRole in other accounts
resource "aws_iam_role_policy" "prod_admin" {
  count = local.is_prod ? 1 : 0
  name  = "sml-elt-prod-policy"
  role  = aws_iam_role.prod_admin[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Full access to prod S3 bucket
      {
        Sid    = "ProdBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.elt.arn,
          "${aws_s3_bucket.elt.arn}/*"
        ]
      },
      # AssumeRole in UAT/DEV/SIT accounts
      {
        Sid    = "AssumeRoleInTargetAccounts"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::${var.uat_account_id}:role/sml-elt-cross-account-uat",
          "arn:aws:iam::${var.dev_account_id}:role/sml-elt-cross-account-dev",
          "arn:aws:iam::${var.sit_account_id}:role/sml-elt-cross-account-sit"
        ]
      }
    ]
  })
}

# Non-Production Environments: Cross-account assumable role
resource "aws_iam_role" "cross_account" {
  count = local.is_prod ? 0 : 1
  name  = "sml-elt-cross-account-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.prod_account_id}:role/sml-elt-admin-prod"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "boomi-elt-${var.environment}"  # Extra security
          }
        }
      }
    ]
  })

  max_session_duration = 3600  # 1 hour

  tags = {
    Name = "Boomi ELT Cross-Account (${upper(var.environment)})"
  }
}

# Non-prod role policy: Access to environment's S3 bucket
resource "aws_iam_role_policy" "cross_account" {
  count = local.is_prod ? 0 : 1
  name  = "sml-elt-${var.environment}-policy"
  role  = aws_iam_role.cross_account[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.elt.arn,
          "${aws_s3_bucket.elt.arn}/*"
        ]
      }
    ]
  })
}

# Instance profile for Boomi atom EC2 instances (prod only)
resource "aws_iam_instance_profile" "prod_admin" {
  count = local.is_prod ? 1 : 0
  name  = "sml-elt-admin-prod"
  role  = aws_iam_role.prod_admin[0].name
}
