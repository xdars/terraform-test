provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

resource "random_pet" "lambda_bucket_name" {
  prefix = "stourage"
  length = 4
}

# Create bucket
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = random_pet.lambda_bucket_name.id
}

resource "aws_s3_bucket_ownership_controls" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "lambda_bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.lambda_bucket]

  bucket = aws_s3_bucket.lambda_bucket.id
  acl    = "private"
}

# Prepare lambdas
data "archive_file" "lambda_callLambda" {
  type        = "zip"
  source_dir  = "${path.module}/callLambda"
  output_path = "${path.module}/callLambda.zip"
}

data "archive_file" "lambda_makeFileLambda" {
  type        = "zip"
  source_dir  = "${path.module}/makeFileLambda"
  output_path = "${path.module}/makeFileLambda.zip"
}

# Upload
resource "aws_s3_object" "lambda_callLambda" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = "callLambda.zip"
  source = data.archive_file.lambda_callLambda.output_path

  etag = filemd5(data.archive_file.lambda_callLambda.output_path)
}

resource "aws_s3_object" "lambda_makeFileLambda" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = "makeFileLambda.zip"
  source = data.archive_file.lambda_makeFileLambda.output_path

  etag = filemd5(data.archive_file.lambda_makeFileLambda.output_path)
}

data "aws_iam_policy_document" "asg_assume_role_policy" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "asg_domain_join_policy" {
  statement {
    actions = [
      "ssm:DescribeAssociation",
      "ssm:GetDocument",
      "ssm:ListAssociations",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceInformation",
      "ssm:CreateAssociation",
      "cloudformation:DescribeStacks",
      "cloudformation:ListStackResources",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "kms:ListAliases",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:ListRoles",
      "lambda:*",
      "logs:DescribeLogGroups",
      "states:DescribeStateMachine",
      "states:ListStateMachines",
      "tag:GetResources",
      "xray:GetTraceSummaries",
      "xray:BatchGetTraces"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lambda-workaround-policy" {
  name        = "test-policy"
  description = "A test policy"
  policy      = data.aws_iam_policy_document.asg_domain_join_policy.json
}


resource "aws_iam_role" "invoke-lambda" {
  name               = "invoke-lambda"
  assume_role_policy = data.aws_iam_policy_document.asg_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "attach-lambda-policies" {
  role       = aws_iam_role.invoke-lambda.name
  policy_arn = aws_iam_policy.lambda-workaround-policy.arn
}

resource "aws_lambda_function" "call_lambda" {
  function_name = "call_lambda_function"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_callLambda.key

  runtime = "nodejs16.x"
  handler = "index.handler"

  source_code_hash = data.archive_file.lambda_callLambda.output_base64sha256

  role = aws_iam_role.invoke-lambda.arn
}

resource "aws_lambda_function" "make_file_lambda" {
  function_name = "make_file_lambda"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_makeFileLambda.key

  runtime = "nodejs16.x"
  handler = "index.handler"

  source_code_hash = data.archive_file.lambda_makeFileLambda.output_base64sha256

  role = aws_iam_role.invoke-lambda.arn
}
