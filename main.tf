provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# Save environment

# Create bucket
resource "aws_s3_bucket" "the_bucket" {
  bucket = "stourage2-ultimately-smoothly-helping-dove"
}

resource "aws_s3_bucket_ownership_controls" "the_bucket" {
  bucket = aws_s3_bucket.the_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# public-read-write is not good; todo: find another way.
resource "aws_s3_bucket_acl" "the_bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.the_bucket]

  bucket = aws_s3_bucket.the_bucket.id
  acl    = "public-read-write"
}

# Bucket policy

resource "aws_s3_bucket_public_access_block" "s3-static-bucket-public-access-block" {
  bucket                  = aws_s3_bucket.the_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
  #depends_on              = [aws_s3_bucket_policy.allow_access_from_another_account]
}

resource "aws_s3_bucket_policy" "allow_access_from_another_account" {
  bucket = aws_s3_bucket.the_bucket.id
  policy = data.aws_iam_policy_document.allow_access_from_another_account.json
}

data "aws_iam_policy_document" "allow_access_from_another_account" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.the_bucket.arn,
      "${aws_s3_bucket.the_bucket.arn}/*",
    ]
  }
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
  bucket = aws_s3_bucket.the_bucket.id
  key    = "callLambda.zip"
  source = data.archive_file.lambda_callLambda.output_path

  etag = filemd5(data.archive_file.lambda_callLambda.output_path)
  tags = {
    env = local.environment
  }
}

resource "aws_s3_object" "lambda_makeFileLambda" {
  bucket = aws_s3_bucket.the_bucket.id
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
  function_name = local.call_lambda_name

  s3_bucket = aws_s3_bucket.the_bucket.id
  s3_key    = aws_s3_object.lambda_callLambda.key

  runtime = "nodejs16.x"
  handler = "index.handler"

  source_code_hash = data.archive_file.lambda_callLambda.output_base64sha256

  role = aws_iam_role.invoke-lambda.arn
}

resource "aws_lambda_function" "make_file_lambda" {
  function_name = local.make_file_lambda_name

  s3_bucket = aws_s3_bucket.the_bucket.id
  s3_key    = aws_s3_object.lambda_makeFileLambda.key

  runtime = "nodejs16.x"
  handler = "index.handler"

  source_code_hash = data.archive_file.lambda_makeFileLambda.output_base64sha256

  role = aws_iam_role.invoke-lambda.arn
}

# API gateway

resource "aws_apigatewayv2_api" "lambda" {
  name          = local.api_gateway_name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id
  name   = local.api_gateway_stage_name

  auto_deploy = true
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw2.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "call_lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.call_lambda.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}


resource "aws_apigatewayv2_route" "hello_world" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.call_lambda.id}"
}

resource "aws_cloudwatch_log_group" "api_gw2" {
  name = "/aws/api_gw2/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw2" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.call_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}
