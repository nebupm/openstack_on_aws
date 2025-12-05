#########################################################
# EVENTBRIDGE SCHEDULER VARIABLES
#########################################################
variable "enable_auto_shutdown" {
  description = "Enable automatic EC2 instance shutdown/startup"
  type        = bool
  default     = true
}

variable "stop_time" {
  description = "Time to stop instance (24hr format, e.g., '18:00' for 6 PM)"
  type        = string
  default     = "18:00"
}

variable "start_time" {
  description = "Time to start instance (24hr format, e.g., '08:00' for 8 AM)"
  type        = string
  default     = "10:00"
}

variable "timezone" {
  description = "Timezone for schedule (e.g., 'Europe/London', 'America/New_York')"
  type        = string
  default     = "Europe/London"
}

variable "start_on_weekdays_only" {
  description = "Start instance only on weekdays (Mon-Fri)"
  type        = bool
  default     = true
}

#########################################################
# EVENTBRIDGE SCHEDULER RESOURCES
#########################################################

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Parse time for cron expressions
locals {
  stop_hour   = split(":", var.stop_time)[0]
  stop_minute = split(":", var.stop_time)[1]
  #start_hour   = split(":", var.start_time)[0]
  #start_minute = split(":", var.start_time)[1]

  # Cron format: cron(minutes hours day month dayofweek year)
  stop_cron = "cron(${local.stop_minute} ${local.stop_hour} ? * * *)"
  #start_cron = var.start_on_weekdays_only ? "cron(${local.start_minute} ${local.start_hour} ? * MON-FRI *)" : "cron(${local.start_minute} ${local.start_hour} ? * * *)"
}

# IAM Role for EventBridge Scheduler
resource "aws_iam_role" "eventbridge_scheduler_role" {
  count = var.create_linux_ec2 && var.enable_auto_shutdown ? 1 : 0
  name  = "eventbridge-kolla-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = {
    Name = "EventBridge Scheduler Role for Kolla Instance"
  }
}

# IAM Policy for EventBridge Scheduler to stop/start EC2
resource "aws_iam_role_policy" "eventbridge_scheduler_policy" {
  count = var.create_linux_ec2 && var.enable_auto_shutdown ? 1 : 0
  name  = "eventbridge-kolla-scheduler-policy"
  role  = aws_iam_role.eventbridge_scheduler_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:StopInstances",
          #          "ec2:StartInstances",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# EventBridge Schedule to STOP instance
resource "aws_scheduler_schedule" "stop_instance" {
  count      = var.create_linux_ec2 && var.enable_auto_shutdown ? 1 : 0
  name       = "stop-kolla-instance-daily"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = local.stop_cron
  schedule_expression_timezone = var.timezone

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.eventbridge_scheduler_role[0].arn

    input = jsonencode({
      InstanceIds = [aws_instance.kolla_instance[0].id]
    })
  }

  description = "Stop Kolla instance daily at ${var.stop_time} ${var.timezone}"
}

# EventBridge Schedule to START instance
#resource "aws_scheduler_schedule" "start_instance" {
#  count      = var.create_linux_ec2 && var.enable_auto_shutdown ? 1 : 0
#  name       = "start-kolla-instance"
#  group_name = "default"

#  flexible_time_window {
#    mode = "OFF"
#  }

#  schedule_expression          = local.start_cron
#  schedule_expression_timezone = var.timezone

#  target {
#    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
#    role_arn = aws_iam_role.eventbridge_scheduler_role[0].arn
#
#    input = jsonencode({
#      InstanceIds = [aws_instance.kolla_instance[0].id]
#    })
#  }

#  description = var.start_on_weekdays_only ? "Start Kolla instance weekdays at ${var.start_time} ${var.timezone}" : "Start Kolla instance daily at ${var.start_time} ${var.timezone}"
#}

#########################################################
# ADDITIONAL OUTPUTS FOR SCHEDULER
#########################################################

output "auto_shutdown_enabled" {
  description = "Whether auto shutdown/startup is enabled"
  value       = var.enable_auto_shutdown
}

output "stop_schedule" {
  description = "Stop schedule configuration"
  value       = var.enable_auto_shutdown ? "${var.stop_time} ${var.timezone} (daily)" : "Disabled"
}

#output "start_schedule" {
#  description = "Start schedule configuration"
#  value = var.enable_auto_shutdown ? (
#    var.start_on_weekdays_only ?
#    "${var.start_time} ${var.timezone} (Mon-Fri)" :
#    "${var.start_time} ${var.timezone} (daily)"
#  ) : "Disabled"
#}