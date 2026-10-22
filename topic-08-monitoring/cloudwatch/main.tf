terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Профіль admin з гайду: CLI бере роль cli-admin-role через student-base.
provider "aws" {
  profile = var.aws_profile
  region  = var.region

  default_tags {
    tags = {
      Project   = "goit-topic-08"
      ManagedBy = "terraform"
    }
  }
}

# --- Мережа з теми 3: не створюємо, а знаходимо за тегами (спершу застосуйте topic-03-vpc)

data "aws_vpc" "main" {
  tags = {
    Project = "goit-topic-03"
    Name    = var.vpc_name
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Name"
    values = ["${var.vpc_name}-public-*"]
  }
}

# SG з теми 3: HTTP зі світу, SSH лише з вашого IP
data "aws_security_group" "web" {
  vpc_id = data.aws_vpc.main.id
  name   = "${var.vpc_name}-web"
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# --- IAM-роль сервера: Session Manager (кнопка Connect) і право агенту CloudWatch писати метрики та логи

resource "aws_iam_role" "ec2" {
  name = "${var.name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ])

  role       = aws_iam_role.ec2.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# --- CloudWatch Logs: сюди агент шле access log Apache.
# Retention обов'язковий: без нього логи зберігаються (і оплачуються) вічно.

resource "aws_cloudwatch_log_group" "access" {
  name              = "/${var.name}/access"
  retention_in_days = 7
}

# --- Сервер, за яким стежимо: Apache + агент CloudWatch (user-data.sh)

resource "aws_instance" "web" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = sort(data.aws_subnets.public.ids)[0]
  vpc_security_group_ids = [data.aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  user_data              = templatefile("${path.module}/user-data.sh", { log_group = aws_cloudwatch_log_group.access.name })

  # Детальний моніторинг: метрики EC2 щохвилини замість кожних 5 хвилин, тож алярм реагує швидше
  monitoring = true

  metadata_options {
    http_tokens = "required"
  }

  # AWS оновлює образ Amazon Linux раз на кілька тижнів — не перестворюємо через це сервер
  lifecycle {
    ignore_changes = [ami]
  }

  tags = { Name = var.name }
}

# --- Сповіщення: Amazon SNS розсилає повідомлення алярмів на email

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- Алярм: CPU понад поріг дві хвилини поспіль → лист «ALARM», повернувся в норму → лист «OK»

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "${var.name}-cpu-high"
  alarm_description   = "CPU сервера ${var.name} понад ${var.cpu_threshold} % дві хвилини поспіль"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.web.id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = var.cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# --- З логів у метрику: кожен рядок access log зі статусом 404 додає 1 до метрики NotFound

locals {
  namespace = "GoIT/Web"
}

resource "aws_cloudwatch_log_metric_filter" "not_found" {
  name           = "${var.name}-404"
  log_group_name = aws_cloudwatch_log_group.access.name

  # Формат combined: IP - user [час] "GET /шлях HTTP/1.1" статус розмір "referrer" "user-agent"
  pattern = "[ip, identity, user, timestamp, request, status = 404, size, referrer, agent]"

  metric_transformation {
    name          = "NotFound"
    namespace     = local.namespace
    value         = "1"
    default_value = "0"
  }
}

# Збережений запит Logs Insights: CloudWatch → Logs Insights → Saved queries
resource "aws_cloudwatch_query_definition" "not_found" {
  name            = "${var.name}/404-by-path"
  log_group_names = [aws_cloudwatch_log_group.access.name]

  query_string = <<-EOT
    parse @message '* * * [*] "* * *" * *' as ip, identity, user, time, method, path, protocol, status, rest
    | filter status = "404"
    | stats count(*) as hits by path
    | sort hits desc
  EOT
}

# --- Дашборд: CPU від EC2, RAM від агента, 404 з логів і самі логи на одному екрані

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.name

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title       = "CPU, % (AWS/EC2)"
          region      = var.region
          stat        = "Average"
          period      = 60
          metrics     = [["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.web.id]]
          annotations = { horizontal = [{ label = "Поріг алярму", value = var.cpu_threshold }] }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title   = "RAM, % (CWAgent — є лише завдяки агенту)"
          region  = var.region
          stat    = "Average"
          period  = 60
          metrics = [["CWAgent", "mem_used_percent", "InstanceId", aws_instance.web.id]]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title   = "Відповіді 404 за хвилину (метрика з логів)"
          region  = var.region
          stat    = "Sum"
          period  = 60
          metrics = [[local.namespace, "NotFound"]]
        }
      },
      {
        type = "log", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Останні запити до сервера"
          region = var.region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.access.name}' | fields @timestamp, @message | sort @timestamp desc | limit 20"
        }
      },
    ]
  })
}
