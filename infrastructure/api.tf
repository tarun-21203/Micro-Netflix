# =================================================================
# API GATEWAY (CORE APPLICATION ROUTING INTEGRATION LAYER)
# =================================================================

resource "aws_api_gateway_rest_api" "netflix_api" {
  name        = "${var.project_name}-api"
  description = "Edge API Gateway routing traffic to Micro-Netflix Serverless Lambdas"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name          = "${var.project_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.netflix_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.users.arn]
}

# -----------------------------------------------------------------
# Route Endpoints: /upload-url
# -----------------------------------------------------------------
resource "aws_api_gateway_resource" "upload" {
  rest_api_id = aws_api_gateway_rest_api.netflix_api.id
  parent_id   = aws_api_gateway_rest_api.netflix_api.root_resource_id
  path_part   = "upload-url"
}

resource "aws_api_gateway_method" "upload_post" {
  rest_api_id   = aws_api_gateway_rest_api.netflix_api.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "upload_integration" {
  rest_api_id             = aws_api_gateway_rest_api.netflix_api.id
  resource_id             = aws_api_gateway_resource.upload.id
  http_method             = aws_api_gateway_method.upload_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_upload_url.invoke_arn
}

resource "aws_api_gateway_method" "upload_options" {
  rest_api_id   = aws_api_gateway_rest_api.netflix_api.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "upload_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.netflix_api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "upload_options_response" {
  rest_api_id = aws_api_gateway_rest_api.netflix_api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "upload_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.netflix_api.id
  resource_id = aws_api_gateway_resource.upload.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = aws_api_gateway_method_response.upload_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Authorization,Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.upload_options_integration]
}

# -----------------------------------------------------------------
# Route Endpoints: /videos
# -----------------------------------------------------------------
resource "aws_api_gateway_resource" "videos" {
  rest_api_id = aws_api_gateway_rest_api.netflix_api.id
  parent_id   = aws_api_gateway_rest_api.netflix_api.root_resource_id
  path_part   = "videos"
}

resource "aws_api_gateway_method" "videos_get" {
  rest_api_id   = aws_api_gateway_rest_api.netflix_api.id
  resource_id   = aws_api_gateway_resource.videos.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "videos_integration" {
  rest_api_id             = aws_api_gateway_rest_api.netflix_api.id
  resource_id             = aws_api_gateway_resource.videos.id
  http_method             = aws_api_gateway_method.videos_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_catalog.invoke_arn
}

resource "aws_api_gateway_method" "videos_options" {
  rest_api_id   = aws_api_gateway_rest_api.netflix_api.id
  resource_id   = aws_api_gateway_resource.videos.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "videos_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.netflix_api.id
  resource_id = aws_api_gateway_resource.videos.id
  http_method = aws_api_gateway_method.videos_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "videos_options_response" {
  rest_api_id = aws_api_gateway_rest_api.netflix_api.id
  resource_id = aws_api_gateway_resource.videos.id
  http_method = aws_api_gateway_method.videos_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "videos_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.netflix_api.id
  resource_id = aws_api_gateway_resource.videos.id
  http_method = aws_api_gateway_method.videos_options.http_method
  status_code = aws_api_gateway_method_response.videos_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Authorization,Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.videos_options_integration]
}

# =================================================================
# MODERNIZED STAGE DEPLOYMENT STATE TRACKER
# =================================================================

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.upload_integration,
    aws_api_gateway_integration_response.upload_options_integration_response,
    aws_api_gateway_integration.videos_integration,
    aws_api_gateway_integration_response.videos_options_integration_response
  ]
  rest_api_id = aws_api_gateway_rest_api.netflix_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.upload.id,
      aws_api_gateway_authorizer.cognito.id,
      aws_api_gateway_method.upload_post.id,
      aws_api_gateway_integration.upload_integration.id,
      aws_api_gateway_method.upload_options.id,
      aws_api_gateway_integration.upload_options_integration.id,
      aws_api_gateway_resource.videos.id,
      aws_api_gateway_method.videos_get.id,
      aws_api_gateway_integration.videos_integration.id,
      aws_api_gateway_method.videos_options.id,
      aws_api_gateway_integration.videos_options_integration.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.netflix_api.id
  stage_name    = "prod"
}

# =================================================================
# INFRASTRUCTURE INVOCATION SECURITY PRIVILEGES
# =================================================================

resource "aws_lambda_permission" "allow_api_gateway_upload" {
  statement_id  = "AllowExecutionFromAPIGatewayUpload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_upload_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.netflix_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_api_gateway_catalog" {
  statement_id  = "AllowExecutionFromAPIGatewayCatalog"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_catalog.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.netflix_api.execution_arn}/*/*"
}

# =================================================================
# SYSTEM OUTPUT MAPPINGS
# =================================================================

output "api_base_url" {
  description = "The target API Gateway endpoint base url string for frontend deployment asset inclusion"
  value       = aws_api_gateway_stage.prod_stage.invoke_url
}
