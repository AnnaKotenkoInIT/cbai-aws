# Тема 5. Контейнеризація в AWS: ECR, ECS, EKS

Terraform-версія практики з теми 5. Три практики — три папки, кожна зі своїм `terraform apply`:

| Папка | Що створює | Слайд |
|---|---|---|
| `ecr/` | ECR-репозиторій `goit-web` + образ з `ecr/app/` (збираєте й пушите самі) | Створення ECR |
| `ecs/` | Кластер ECS, Task Definition і Service на **Fargate** | Створення ECS |
| `eks/` | Кластер EKS, Node Group з одного EC2-вузла; застосунок — через `kubectl` | Створення EKS |

Образ **один** для ECS і EKS. Контейнер — nginx зі сторінкою, яка показує, **де вона запущена**:
- в ECS — кластер, ID задачі та AZ;
- в EKS — под, namespace, вузол та IP пода;
- локально — «Docker · локально».

## Передумови

- Профіль `admin` з гайду: `aws sts get-caller-identity --profile admin`.
- **Застосована тема 3** (`topic-03-vpc`). Усе запускається в її публічних підмережах, NAT не потрібен.
- Docker (Docker Desktop) — для збирання образу.
- `kubectl` — для практики EKS.

## 1. ECR: репозиторій і образ

```bash
cd topic-05-containers/ecr
terraform init
terraform apply

REPO=$(terraform output -raw repository_url)

# Логін Docker в ECR (токен діє 12 год)
aws ecr get-login-password --profile admin --region eu-central-1 \
  | docker login --username AWS --password-stdin ${REPO%%/*}

# Збираємо під linux/amd64 (так працюють Fargate і вузли EKS; важливо на Mac з Apple Silicon) і пушимо
docker build --platform linux/amd64 -t $REPO:v1 app
docker push $REPO:v1

aws ecr describe-images --profile admin --repository-name goit-web --output table
```

Перевірити образ локально: `docker run --rm -p 8080:80 $REPO:v1` → http://localhost:8080.

## 2. ECS: контейнер на Fargate

```bash
cd ../ecs
terraform init
terraform apply
```

Задача отримує публічний IP у підмережі теми 3. Знайти його можна так:

```bash
TASK=$(aws ecs list-tasks --profile admin --cluster goit-ecs --query 'taskArns[0]' --output text)
ENI=$(aws ecs describe-tasks --profile admin --cluster goit-ecs --tasks $TASK \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
aws ec2 describe-network-interfaces --profile admin --network-interface-ids $ENI \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text
```

Відкрийте `http://<IP>`: сторінка покаже **Amazon ECS · FARGATE**, кластер, задачу й AZ.

Масштабувати можна змінною: `terraform apply -var desired_count=2`. У кожної задачі буде свій IP і своя сторінка.

## 3. EKS: Kubernetes-кластер

Створення кластера займає **~15 хвилин**.

```bash
cd ../eks
terraform init
terraform apply

# Налаштувати kubectl на новий кластер
$(terraform output -raw kubeconfig_command)
kubectl get nodes

# Задеплоїти застосунок: Deployment (2 поди) + Service NodePort 30080
terraform output -raw k8s_manifest | kubectl apply -f -
kubectl get pods -o wide
kubectl get svc web
```

Сторінка доступна на публічному IP вузла, порт 30080:

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
echo http://$NODE_IP:30080
```

Сторінка покаже **Amazon EKS · Kubernetes**, ім'я пода та вузла. Оновлюйте її: Service розподіляє запити між двома подами.

Масштабування подів: `kubectl scale deployment web --replicas=3`.

## Прибирання — обов'язково після заняття

У зворотному порядку:

```bash
cd topic-05-containers/eks && terraform destroy   # ~10 хв
cd ../ecs && terraform destroy
cd ../ecr && terraform destroy                    # видаляє репозиторій разом з образами
```

Тему 3 (`topic-03-vpc`) видаляйте, лише якщо мережа більше не потрібна.

## Вартість

| Ресурс | Приблизно |
|---|---|
| ECR | $0.10 за ГБ на місяць (образ ~25 МБ) |
| ECS Fargate, 0.25 vCPU / 0.5 ГБ | ≈ $0.012/год за задачу |
| EKS: кластер (control plane) | $0.10/год |
| EKS: вузол t3.small | ≈ $0.024/год |
| Публічні IPv4 (задача, вузол) | ≈ $0.005/год кожна |

Заняття, після якого все видалено, коштує **менше $1**. EKS, забутий на добу, — близько $3.

## Типові помилки

| Симптом | Причина / що зробити |
|---|---|
| `no matching EC2 VPC found` | Не застосовано `topic-03-vpc` |
| `couldn't find resource` для ECR в `ecs/` чи `eks/` | Спершу `terraform apply` у `ecr/` |
| Задача ECS зупиняється з `CannotPullContainerError` | Образ не запушено або не той тег — перевірте `aws ecr describe-images` |
| `exec format error` у логах задачі чи пода | Образ зібрано під ARM — перезберіть з `--platform linux/amd64` і запуште знову |
| Под у стані `ImagePullBackOff` | Те саме: немає образу `goit-web:v1` в ECR |
| `kubectl`: `You must be logged in to the server` | Не виконано команду з `terraform output -raw kubeconfig_command` або інший профіль AWS |
