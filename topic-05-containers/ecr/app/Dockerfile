FROM nginx:alpine

# Офіційний образ nginx виконує скрипти з /docker-entrypoint.d/ перед стартом сервера:
# наш скрипт визначає, де запущено контейнер (ECS / EKS / локально), і пише index.html.
COPY --chmod=755 40-page.sh /docker-entrypoint.d/40-page.sh
