#!/bin/sh
# Пише /usr/share/nginx/html/index.html з інформацією про те, де працює контейнер.
set -e

row() { printf '<dt>%s</dt><dd>%s</dd>\n' "$1" "$2"; }

if [ -n "$ECS_CONTAINER_METADATA_URI_V4" ]; then
  # ECS сам передає в контейнер адресу Task Metadata endpoint
  META=$(wget -qO- "$ECS_CONTAINER_METADATA_URI_V4/task")
  field() { echo "$META" | grep -o "\"$1\": *\"[^\"]*\"" | head -n1 | sed 's/.*"\([^"]*\)"$/\1/'; }
  CLUSTER=$(field Cluster)
  TASK=$(field TaskARN)
  PLATFORM="Amazon ECS · $(field LaunchType)"
  ROWS="$(row Cluster "${CLUSTER##*/}")$(row Task "${TASK##*/}")$(row 'Availability Zone' "$(field AvailabilityZone)")"
elif [ -n "$KUBERNETES_SERVICE_HOST" ]; then
  # Kubernetes завжди задає KUBERNETES_SERVICE_HOST; решту передає Downward API з маніфесту
  PLATFORM="Amazon EKS · Kubernetes"
  ROWS="$(row Pod "$POD_NAME")$(row Namespace "$POD_NAMESPACE")$(row Node "$NODE_NAME")$(row 'Pod IP' "$POD_IP")"
else
  PLATFORM="Docker · локально"
  ROWS=""
fi

cat > /usr/share/nginx/html/index.html <<EOF
<!doctype html>
<html lang="uk">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${PLATFORM}</title>
  <style>
    body { margin: 0; min-height: 100vh; display: grid; place-items: center;
           font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0; }
    main { text-align: center; padding: 16px; }
    h1 { font-size: 1rem; font-weight: 500; color: #94a3b8; margin: 0 0 12px; }
    .where { font-size: clamp(1.5rem, 6vw, 3rem); color: #f97316; margin: 0 0 24px; }
    dl { display: grid; grid-template-columns: auto auto; gap: 6px 16px; justify-content: center; margin: 0; }
    dt { color: #94a3b8; text-align: right; }
    dd { margin: 0; text-align: left; font-family: ui-monospace, monospace; word-break: break-all; }
  </style>
</head>
<body>
  <main>
    <h1>GoIT · Тема 5 · Контейнеризація в AWS</h1>
    <p class="where">${PLATFORM}</p>
    <dl>
      ${ROWS}
      $(row Hostname "$(hostname)")
    </dl>
  </main>
</body>
</html>
EOF
