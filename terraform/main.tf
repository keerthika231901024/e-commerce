provider "aws" {
  region  = var.region
  profile = var.profile
}

data "archive_file" "order_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/order/lambda_function.py"
  output_path = "${path.module}/order_lambda.zip"
}

data "archive_file" "auth_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/auth/lambda_function.py"
  output_path = "${path.module}/auth_lambda.zip"
}

# =========================
# S3 BUCKET
# =========================
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.project_name}-frontend-bucket-123"
  force_destroy = true

  tags = {
    Name  = "keerthi-frontend"
    Owner = "keerthi"
  }
}

# =========================
# PUBLIC ACCESS SETTINGS
# =========================
resource "aws_s3_bucket_public_access_block" "public" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# =========================
# WEBSITE HOSTING
# =========================
resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }
}

# =========================
# BUCKET POLICY (PUBLIC READ)
# =========================
resource "aws_s3_bucket_policy" "policy" {
  bucket = aws_s3_bucket.frontend.id

  depends_on = [
    aws_s3_bucket_public_access_block.public
  ]

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = "*",
      Action    = ["s3:GetObject"],
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
    }]
  })
}

# =========================
# UPLOAD FILES (AUTO UPDATE)
# =========================

# HTML
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "${path.module}/../frontend/pages/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/../frontend/pages/index.html")
}

# CART HTML
resource "aws_s3_object" "cart" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "cart.html"
  source       = "${path.module}/../frontend/pages/cart.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/../frontend/pages/cart.html")
}

# ORDERS HTML
resource "aws_s3_object" "orders" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "orders.html"
  source       = "${path.module}/../frontend/pages/orders.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/../frontend/pages/orders.html")
}

# LOGIN HTML
resource "aws_s3_object" "login" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "login.html"
  source       = "${path.module}/../frontend/pages/login.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/../frontend/pages/login.html")
}

# WEBSITE TEST HTML
resource "aws_s3_object" "website_test" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "website.test.html"
  source       = "${path.module}/../frontend/website.test.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/../frontend/website.test.html")
}

# CSS
resource "aws_s3_object" "css" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "css/style.css"
  source       = "${path.module}/../frontend/css/style.css"
  content_type = "text/css"
  etag         = filemd5("${path.module}/../frontend/css/style.css")
}

# JS
resource "aws_s3_object" "js" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "js/script.js"
  source       = "${path.module}/../frontend/js/script.js"
  content_type = "application/javascript"
  etag         = filemd5("${path.module}/../frontend/js/script.js")
}

# =========================
# ORDER SERVICE (DYNAMODB + LAMBDA + API)
# =========================
resource "aws_dynamodb_table" "orders" {
  name         = "${var.project_name}_orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  tags = {
    Name  = "keerthi-orders"
    Owner = "keerthi"
  }
}

resource "aws_iam_role" "order_lambda_role" {
  name = "${var.project_name}-order-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "order_lambda_policy" {
  name = "${var.project_name}-order-lambda-policy"
  role = aws_iam_role.order_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Scan"
        ],
        Resource = aws_dynamodb_table.orders.arn
      },
      {
        Effect = "Allow",
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "order" {
  function_name    = "keerthi_order"
  role             = aws_iam_role.order_lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.order_lambda_zip.output_path
  source_code_hash = data.archive_file.order_lambda_zip.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      ORDER_TABLE = aws_dynamodb_table.orders.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_dynamodb_table" "keerthi_table" {
  name         = "KEERTHI_TABLE"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "email"

  attribute {
    name = "email"
    type = "S"
  }

  tags = {
    Name  = "keerthi-auth-users"
    Owner = "keerthi"
  }
}

resource "aws_dynamodb_table" "keerthi_session_table" {
  name         = "KEERTHI_SESSION_TABLE"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"

  attribute {
    name = "session_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = {
    Name  = "keerthi-auth-sessions"
    Owner = "keerthi"
  }
}

resource "aws_iam_role" "auth_lambda_role" {
  name = "${var.project_name}-auth-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "auth_lambda_policy" {
  name = "${var.project_name}-auth-lambda-policy"
  role = aws_iam_role.auth_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ],
        Resource = [
          aws_dynamodb_table.keerthi_table.arn,
          aws_dynamodb_table.keerthi_session_table.arn,
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "auth" {
  function_name    = "KEERTHI_AUTH_SERVICE"
  role             = aws_iam_role.auth_lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.auth_lambda_zip.output_path
  source_code_hash = data.archive_file.auth_lambda_zip.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      KEERTHI_TABLE               = aws_dynamodb_table.keerthi_table.name
      KEERTHI_SESSION_TABLE       = aws_dynamodb_table.keerthi_session_table.name
      KEERTHI_SESSION_TTL_SECONDS = "86400"
      KEERTHI_COOKIE_SECURE       = "true"
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "auth_lambda_logs" {
  count             = var.enable_monitoring ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.auth.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "order_lambda_logs" {
  count             = var.enable_monitoring ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.order.function_name}"
  retention_in_days = 14
}

resource "aws_sns_topic" "monitoring_alerts" {
  name = "${var.project_name}-service-monitoring-alerts"
}

resource "aws_sns_topic_subscription" "monitoring_email" {
  count     = var.enable_monitoring && var.monitoring_email == "" ? 0 : var.enable_monitoring ? 1 : 0
  topic_arn = aws_sns_topic.monitoring_alerts.arn
  protocol  = "email"
  endpoint  = var.monitoring_email
}

resource "aws_cloudwatch_metric_alarm" "order_lambda_errors" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-order-lambda-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alarm when order lambda has errors"
  alarm_actions       = [aws_sns_topic.monitoring_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.order.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "orders_api_5xx" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-orders-api-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "5xx"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alarm when orders API returns 5xx"
  alarm_actions       = [aws_sns_topic.monitoring_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.orders.id
  }
}

resource "aws_cloudwatch_metric_alarm" "orders_table_throttles" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-orders-dynamodb-throttles"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alarm when orders table is throttled"
  alarm_actions       = [aws_sns_topic.monitoring_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.orders.name
  }
}

resource "aws_cloudwatch_dashboard" "service_monitoring" {
  count          = var.enable_monitoring ? 1 : 0
  dashboard_name = "${var.project_name}-service-monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Lambda Invocations & Errors"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.product_lambda_name, { "label" : "Product Invocations" }],
            ["AWS/Lambda", "Errors", "FunctionName", var.product_lambda_name, { "label" : "Product Errors" }],
            ["AWS/Lambda", "Invocations", "FunctionName", var.cart_lambda_name, { "label" : "Cart Invocations" }],
            ["AWS/Lambda", "Errors", "FunctionName", var.cart_lambda_name, { "label" : "Cart Errors" }],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.order.function_name, { "label" : "Order Invocations" }],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.order.function_name, { "label" : "Order Errors" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Lambda Duration (p95)"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.product_lambda_name, { "stat" : "p95", "label" : "Product p95" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.cart_lambda_name, { "stat" : "p95", "label" : "Cart p95" }],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.order.function_name, { "stat" : "p95", "label" : "Order p95" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Orders API Metrics"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.orders.id, { "label" : "Requests" }],
            ["AWS/ApiGateway", "4xx", "ApiId", aws_apigatewayv2_api.orders.id, { "label" : "4xx" }],
            ["AWS/ApiGateway", "5xx", "ApiId", aws_apigatewayv2_api.orders.id, { "label" : "5xx" }],
            ["AWS/ApiGateway", "Latency", "ApiId", aws_apigatewayv2_api.orders.id, { "label" : "Latency" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Orders DynamoDB Metrics"
          view    = "timeSeries"
          stacked = false
          region  = var.region
          metrics = [
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.orders.name, { "label" : "Consumed Write" }],
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.orders.name, { "label" : "Consumed Read" }],
            ["AWS/DynamoDB", "WriteThrottleEvents", "TableName", aws_dynamodb_table.orders.name, { "label" : "Write Throttles" }],
            ["AWS/DynamoDB", "ReadThrottleEvents", "TableName", aws_dynamodb_table.orders.name, { "label" : "Read Throttles" }]
          ]
        }
      }
    ]
  })
}

resource "aws_apigatewayv2_api" "orders" {
  name          = "${var.project_name}-orders-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins     = var.auth_allowed_origins
    allow_methods     = ["GET", "POST", "OPTIONS"]
    allow_headers     = ["*"]
    allow_credentials = true
  }
}

resource "aws_apigatewayv2_integration" "orders_lambda" {
  api_id                 = aws_apigatewayv2_api.orders.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.order.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "orders_post" {
  api_id    = aws_apigatewayv2_api.orders.id
  route_key = "POST /orders"
  target    = "integrations/${aws_apigatewayv2_integration.orders_lambda.id}"
}

resource "aws_apigatewayv2_route" "orders_get" {
  api_id    = aws_apigatewayv2_api.orders.id
  route_key = "GET /orders"
  target    = "integrations/${aws_apigatewayv2_integration.orders_lambda.id}"
}

resource "aws_apigatewayv2_stage" "orders_default" {
  api_id      = aws_apigatewayv2_api.orders.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "orders_api_invoke" {
  statement_id  = "AllowExecutionFromAPIGatewayOrdersV2"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.orders.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "auth_lambda" {
  api_id                 = aws_apigatewayv2_api.orders.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.auth.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "auth_login" {
  api_id    = aws_apigatewayv2_api.orders.id
  route_key = "POST /auth/login"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda.id}"
}

resource "aws_apigatewayv2_route" "auth_register" {
  api_id    = aws_apigatewayv2_api.orders.id
  route_key = "POST /auth/register"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda.id}"
}

resource "aws_apigatewayv2_route" "auth_me" {
  api_id    = aws_apigatewayv2_api.orders.id
  route_key = "GET /auth/me"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda.id}"
}

resource "aws_apigatewayv2_route" "auth_logout" {
  api_id    = aws_apigatewayv2_api.orders.id
  route_key = "POST /auth/logout"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda.id}"
}

resource "aws_lambda_permission" "auth_api_invoke" {
  statement_id  = "AllowExecutionFromAPIGatewayAuth"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.orders.execution_arn}/*/*"
}

# =========================
# CLOUDFRONT
# =========================
resource "aws_cloudfront_distribution" "cdn" {

  origin {
    domain_name = aws_s3_bucket.frontend.website_endpoint
    origin_id   = "keerthi-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    target_origin_id       = "keerthi-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name  = "keerthi-cdn"
    Owner = "keerthi"
  }
}

# =========================
# OUTPUT
# =========================
output "frontend_url" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "orders_api_url" {
  value = format("%sorders", aws_apigatewayv2_stage.orders_default.invoke_url)
}

output "monitoring_dashboard_name" {
  value = var.enable_monitoring ? aws_cloudwatch_dashboard.service_monitoring[0].dashboard_name : null
}

output "monitoring_alert_topic_arn" {
  value = aws_sns_topic.monitoring_alerts.arn
}