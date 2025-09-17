# --- IAM Role and Policy for Lambda. This section creates the permissions our Lambda function ---

# IAM Role that the Lambda function will assume.
resource "aws_iam_role" "lambda_exec_role" {
  name = "resource-cleaner-lambda-role"

  # Trust policy allowing Lambda to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy with required permissions. Permission work with snapshots, VPC and logging
resource "aws_iam_policy" "lambda_policy" {
  name        = "resource-cleaner-lambda-policy"
  description = "Allows Lambda to run in subnet, describe EC2 snapshots and write to CloudWatch Logs."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeSnapshots",
          "ec2:DeleteSnapshot"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach the policy to the role.
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_security_group" "lambda_sg" {
  name        = "resource-cleaner-lambda-sg"
  description = "Allow all outbound traffic for the resource-cleaner Lambda"
  vpc_id      = module.vpc.vpc_id

  # Allow the function to send traffic to the internet (e.g., to AWS APIs)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "resource-cleaner-lambda-sg"
  }
}



# --- Lambda Function and Deployment Package ---

# Package the Python script into a zip file.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_function"
  output_path = "${path.module}/lambda_function.zip"
}

# Create the Lambda function resource.
resource "aws_lambda_function" "resource_cleaner" {
  function_name    = "resource-cleaner"
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_exec_role.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Increase timeout if you expect a large number of snapshots
  timeout = 30

  environment {
    variables = {
      # By default, the function will NOT delete anything.
      # Change this to "false" to enable actual deletions.
      dry_run = "true"
    }
  }

  vpc_config {
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  #depends_on = [
  #  aws_iam_role_policy_attachment.lambda_policy_attach
  #]
}

# --- EventBridge Trigger ---

# Create an EventBridge rule that triggers on a schedule.
resource "aws_cloudwatch_event_rule" "every_12_hours" {
  name                = "run-resource-cleaner-every-12-hours"
  description         = "Triggers the resource-cleaner Lambda every 12 hours"
  schedule_expression = "rate(5 minutes)"
  #schedule_expression = "rate(12 hours)"
}

# Set the Lambda function as the target for the rule.
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.every_12_hours.name
  target_id = "ResourceCleanerLambda"
  arn       = aws_lambda_function.resource_cleaner.arn
}

# Grant EventBridge permission to invoke the Lambda function.
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resource_cleaner.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_12_hours.arn
}