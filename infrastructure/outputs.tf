output "frontend_url" {
  value       = "https://${aws_s3_bucket.frontend_site.bucket_regional_domain_name}/index.html"
  description = "Public HTTPS endpoint for the React application"
}

output "frontend_staging_bucket" {
  value       = aws_s3_bucket.frontend_staging.id
  description = "S3 Staging Bucket for CodeDeploy Revisions"
}

output "frontend_site_bucket" {
  value       = aws_s3_bucket.frontend_site.id
  description = "S3 bucket hosting the compiled React static site"
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.users.id
  description = "Cognito user pool id"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.frontend.id
  description = "Cognito frontend app client id"
}

output "cognito_hosted_ui_domain" {
  value       = "https://${aws_cognito_user_pool_domain.frontend.domain}.auth.${var.aws_region}.amazoncognito.com"
  description = "Cognito hosted UI domain"
}

output "codedeploy_application_name" {
  value = aws_codedeploy_app.frontend_app.name
}

output "codedeploy_deployment_group" {
  value = aws_codedeploy_deployment_group.frontend_dg.deployment_group_name
}
