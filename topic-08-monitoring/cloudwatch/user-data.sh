#!/bin/bash
# Виконується один раз при першому запуску: Apache зі сторінкою + агент CloudWatch.
# Це шаблон Terraform (templatefile): $${...} — для Terraform, у bash змінні пишемо без фігурних дужок.
dnf install -y httpd amazon-cloudwatch-agent

TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

cat > /var/www/html/index.html <<EOF
<!doctype html>
<html lang="uk">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$INSTANCE_ID</title>
  <style>
    body { margin: 0; min-height: 100vh; display: grid; place-items: center;
           font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0; }
    main { text-align: center; padding: 16px; }
    h1 { font-size: 1rem; font-weight: 500; color: #94a3b8; margin: 0 0 12px; }
    .id { font-family: ui-monospace, monospace; font-size: clamp(1.5rem, 6vw, 3rem); color: #f97316; margin: 0 0 24px; }
    a { color: #f97316; }
  </style>
</head>
<body>
  <main>
    <h1>GoIT · Тема 8 · Amazon CloudWatch</h1>
    <p class="id">$INSTANCE_ID</p>
    <p>Кожен запит до цього сервера потрапляє в CloudWatch Logs.<br>Спробуйте <a href="/missing">неіснуючу сторінку</a> — це відповідь 404.</p>
  </main>
</body>
</html>
EOF

systemctl enable --now httpd

# Агент: RAM (EC2 сам її не бачить) і access log Apache → лог-група з Terraform
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
{
  "agent": { "run_as_user": "root" },
  "metrics": {
    "append_dimensions": { "InstanceId": "$${aws:InstanceId}" },
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"], "metrics_collection_interval": 60 }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          { "file_path": "/var/log/httpd/access_log", "log_group_name": "${log_group}", "log_stream_name": "{instance_id}" }
        ]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
