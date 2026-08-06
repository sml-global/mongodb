# S3 Bucket for Boomi ELT documents
resource "aws_s3_bucket" "elt" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true  # Safety: prevent accidental deletion
  }
}

# Block public access (enforce private bucket)
resource "aws_s3_bucket_public_access_block" "elt" {
  bucket = aws_s3_bucket.elt.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning (for accidental deletion recovery)
resource "aws_s3_bucket_versioning" "elt" {
  bucket = aws_s3_bucket.elt.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# Server-side encryption (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "elt" {
  bucket = aws_s3_bucket.elt.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # Can upgrade to "aws:kms" for KMS encryption
    }
    bucket_key_enabled = true
  }
}

# Lifecycle policy (move old objects to Infrequent Access)
resource "aws_s3_bucket_lifecycle_configuration" "elt" {
  bucket = aws_s3_bucket.elt.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = var.lifecycle_days
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Bucket policy (allow cross-account access from prod if non-prod environment)
resource "aws_s3_bucket_policy" "elt" {
  count  = local.is_prod ? 0 : 1
  bucket = aws_s3_bucket.elt.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowProdCrossAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.prod_account_id}:role/sml-elt-admin-prod"
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.elt.arn,
          "${aws_s3_bucket.elt.arn}/*"
        ]
      }
    ]
  })
}
