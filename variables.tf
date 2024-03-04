variable "aws_region" {
  description = "AWS region for all resources."

  type    = string
  default = "us-east-1"
}

variable "workspace_to_environment_map" {
  type = map(string)
  default = {
    dev = "dev"
    prd = "prd"
  }
}

locals {
  environment            = lookup(var.workspace_to_environment_map, terraform.workspace, "dev")
  api_gateway_name       = "${local.environment}-api_gateway"
  api_gateway_stage_name = "${local.environment}-api_gateway_stage"

  make_file_lambda_name = "${local.environment}-make-file-lambda"
  call_lambda_name      = "${local.environment}-call-lambda"
}
