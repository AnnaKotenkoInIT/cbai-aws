# Тема 9. Розгортання та DevOps: AWS CLI, Lambda, Elastic Beanstalk

Практика з теми 9. AWS CLI не потребує Terraform, а Lambda й Elastic Beanstalk мають окремі папки, кожна зі своїм `terraform apply`:

| Частина | Що робимо | Слайд |
|---|---|---|
| 1. AWS CLI | Команди: профілі, `--query`, сухий запуск сервера | AWS CLI |
| 2. `lambda/` | Функція **AWS Lambda** рахує суми з CSV, щойно файл потрапляє в S3. Невдалі події йдуть у чергу SQS | Створення Lambda |
| 3. `beanstalk/` | Flask-застосунок на **Elastic Beanstalk** за балансувальником. Нову версію викочуємо через AWS CLI, як це робив би CI/CD | Створення Elastic Beanstalk |

## Передумови

- Профіль `admin` з гайду: `aws sts get-caller-identity --profile admin`.
- Для частини 3 — **застосована тема 3** (`topic-03-vpc`): Beanstalk запускає сервери в її публічних підмережах. Lambda мережа не потрібна.

## 1. AWS CLI

AWS CLI — це той самий API, що й за кнопками консолі, тільки з терміналу. Тому все, що ви робите командами, можна записати в скрипт і запускати автоматично.

**Хто я і під яким профілем:**

```bash
aws --version
aws configure list-profiles                  # профілі з ~/.aws/config
aws sts get-caller-identity --profile admin  # акаунт і роль, під якими працюють команди
```

Профіль — це іменований набір облікових даних і регіону. У реальній роботі є профілі для Dev, Stage і Prod, і `--profile` перемикає між ними. Щоб не писати прапорець у кожній команді: `export AWS_PROFILE=admin`.

**Фільтр виводу `--query`.** AWS повертає великий JSON. Параметр `--query` (мова JMESPath) лишає з нього тільки потрібне, а `--output` задає формат:

```bash
aws ec2 describe-regions --profile admin                     # повний JSON
aws ec2 describe-regions --profile admin \
  --query 'Regions[].RegionName' --output text               # лише назви регіонів

# Усі сервери: ID, тип, стан, публічний IP — таблицею
aws ec2 describe-instances --profile admin \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,PublicIpAddress]' --output table
```

**Команда зі слайда, але безпечно.** `--dry-run` перевіряє права і параметри, але сервер не створює:

```bash
# Актуальний образ Amazon Linux 2023 — AWS публікує його ID у Parameter Store
AMI=$(aws ssm get-parameter --profile admin \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)

aws ec2 run-instances --profile admin --image-id $AMI --instance-type t3.micro --dry-run
# An error occurred (DryRunOperation) ... Request would have succeeded, but DryRun flag is set.
```

Без `--dry-run` ця команда за секунду запустила б сервер.

**Довідка:** `aws ec2 run-instances help` описує всі параметри команди.

**AWS CloudShell.** Якщо під рукою немає комп'ютера з налаштованим CLI, натисніть в консолі AWS іконку `>_` угорі. Відкриється термінал у браузері, вже авторизований під вашим користувачем, з готовим `aws`.

## 2. AWS Lambda: код, який запускає подія

```bash
cd topic-09-devops/lambda
terraform init
terraform apply      # ~40 с
```

```
aws s3 cp ─▶ S3: incoming/*.csv ──подія──▶ Lambda goit-orders ──▶ S3: reports/*.json
                                                  │ помилка
                                                  ▼
                                           SQS: goit-orders-failed
```

Terraform пакує `src/handler.py` у zip і завантажує в Lambda. Функція не працює постійно. S3 викликає її на кожен новий `.csv` у `incoming/`, а оплата йде за мілісекунди виконання.

Звіти функція пише в `reports/`, а не в `incoming/`. Якби звіт потрапляв туди, звідки приходять події, функція викликала б сама себе без кінця.

Відкрийте логи функції в другому терміналі:

```bash
cd topic-09-devops/lambda
aws logs tail $(terraform output -raw log_group) --follow --profile admin
```

### Крок 1. Завантажте файл — отримайте звіт

```bash
B=$(terraform output -raw bucket_name)
aws s3 cp samples/orders-monday.csv s3://$B/incoming/ --profile admin

aws s3 cp s3://$B/reports/orders-monday.json - --profile admin
```

За секунду-дві з'явиться звіт: кількість замовлень, загальна сума і суми по товарах.

### Крок 2. Холодний і теплий старт

У логах після кожного виклику є рядок `REPORT`. Порівняйте перший виклик і повторний:

```bash
aws s3 cp samples/orders-monday.csv s3://$B/incoming/orders-tuesday.csv --profile admin
```

| | Перший виклик (холодний старт) | Повторний (теплий) |
|---|---|---|
| `Init Duration` | ~500 мс | немає |
| `Billed Duration` | ~1200 мс | ~250 мс |

На першому виклику Lambda піднімає контейнер, запускає Python і виконує код поза функцією `handler`, наприклад створення клієнта `boto3`. Це **холодний старт**. Наступні виклики потрапляють у вже теплий контейнер. Якщо функцію довго не викликати, контейнер зникне, і наступний виклик знову буде холодним. Для критичних до затримки API холодні старти прибирає **Provisioned Concurrency**, але вона платна.

Якщо завантажити кілька файлів одночасно, Lambda запустить кілька контейнерів паралельно. Так виглядає масштабування без серверів.

### Крок 3. Що буде з помилкою

```bash
aws s3 cp samples/orders-broken.csv s3://$B/incoming/ --profile admin
```

У файлі немає колонок `qty` і `price`, тому функція впаде з `KeyError: 'qty'` (видно в логах). Подія не губиться: вона потрапляє в чергу **SQS** `goit-orders-failed`, тобто в Dead Letter Queue:

```bash
aws sqs receive-message --profile admin --queue-url $(terraform output -raw failed_queue_url) \
  --query 'Messages[0].Body' --output text | python3 -m json.tool
```

У повідомленні є вихідна подія (`requestPayload`: який файл), причина (`condition: RetriesExhausted`) і помилка (`responsePayload.errorMessage`). Файл можна виправити й обробити повторно.

За замовчуванням Lambda повторює невдалий асинхронний виклик ще двічі, протягом ~3 хвилин. Terraform вимикає повтори (`maximum_retry_attempts = 0`), щоб подія потрапила в чергу одразу.

### У консолі

**Lambda → Functions → goit-orders:**
- **Code** — код функції;
- **Configuration → Triggers** — тригер S3;
- **Configuration → Destinations** — черга для помилок;
- **Monitor** — метрики Invocations, Errors і Duration у CloudWatch (тема 8).

## 3. Elastic Beanstalk: завантажили код — отримали середовище

```bash
cd ../beanstalk
terraform init
terraform apply      # ~3–4 хв
```

Terraform описує лише застосунок, версію коду та налаштування. Усе інше Beanstalk створює сам: балансувальник (ALB), групу Auto Scaling, сервер, security groups і алярми масштабування. Подивитися на це можна так:
- **CloudFormation → Stacks → awseb-…-stack → Resources** — усе, що створив Beanstalk;
- **Elastic Beanstalk → Environments → goit-app-env** — здоров'я (Health), події (Events), логи (Logs) і налаштування (Configuration).

```bash
open $(terraform output -raw url)      # Linux: xdg-open; або скопіюйте URL у браузер
```

Сторінка показує **версію коду**, сервер, який відповів, і час збирання. Цей час записала команда з `app/.ebextensions/01-build-info.config`.

Що в папці `app/`:

| Файл | Навіщо |
|---|---|
| `application.py` | Flask-застосунок. Beanstalk шукає в ньому об'єкт `application` |
| `requirements.txt` | Залежності. Beanstalk сам виконує `pip install` на сервері |
| `.ebextensions/*.config` | Команди й налаштування, які Beanstalk виконує під час кожного розгортання |

### Нова версія через AWS CLI — так працює CI/CD

Відкрийте `app/application.py` і замініть `VERSION = "1"` на `VERSION = "2"`. Далі ті самі команди, які виконав би пайплайн після кожного коміту:

```bash
B=$(terraform output -raw bucket_name)

# 1. Запакувати код. application.py має лежати в корені архіву, а не в папці app/
(cd app && zip -r ../v2.zip .)

# 2. Завантажити архів у S3 і зареєструвати як версію застосунку
aws s3 cp v2.zip s3://$B/versions/v2.zip --profile admin
aws elasticbeanstalk create-application-version --profile admin --application-name goit-app \
  --version-label v2 --source-bundle S3Bucket=$B,S3Key=versions/v2.zip

# 3. Розгорнути версію в середовищі й дочекатися кінця (~1 хв)
aws elasticbeanstalk update-environment --profile admin --environment-name goit-app-env --version-label v2
aws elasticbeanstalk wait environment-updated --profile admin --environment-names goit-app-env
```

Оновіть сторінку: тепер там **Версія 2** і новий час збирання. Хід розгортання видно у вкладці **Events**.

**Відкат** — це розгортання попередньої версії:

```bash
aws elasticbeanstalk describe-application-versions --profile admin --application-name goit-app \
  --query 'ApplicationVersions[].[VersionLabel,DateCreated]' --output table

aws elasticbeanstalk update-environment --profile admin --environment-name goit-app-env \
  --version-label <мітка tf-… з таблиці>
```

Terraform розгортає тільки першу версію (`lifecycle { ignore_changes = [version_label] }`) і далі не повертає середовище до неї. Інфраструктурою керує Terraform, а версіями коду — пайплайн.

Після практики поверніть `VERSION = "1"`, щоб у git не лишилось змін.

**Blue/Green.** Щоб оновлення відбулося зовсім без простою, створюють друге («зелене») середовище з новою версією, перевіряють його, а потім натискають **Actions → Swap environment domain** (`aws elasticbeanstalk swap-environment-cnames`). Адреси двох середовищ міняються місцями, і користувачі одразу потрапляють на нову версію.

## Прибирання — обов'язково після заняття

```bash
cd topic-09-devops/beanstalk && terraform destroy    # ~4 хв: Beanstalk видаляє ALB, сервери, стек
cd ../lambda && terraform destroy
```

Beanstalk тримає службові файли в бакеті `elasticbeanstalk-eu-central-1-<номер акаунта>`. Якщо такого бакета не було, Beanstalk створює його сам, і після `destroy` бакет лишається. Там кілька кілобайтів, тож практично безкоштовно.

## Вартість

| Ресурс | Приблизно |
|---|---|
| Lambda | 1 млн викликів і 400 000 ГБ·с на місяць безкоштовно. Практика коштує $0 |
| SQS, S3 | 1 млн запитів SQS безкоштовно, S3 — копійки |
| Elastic Beanstalk | Сам сервіс безкоштовний, оплачуються ресурси, які він створив: |
| — ALB | ≈ $0.027/год |
| — EC2 t3.micro | ≈ $0.012/год |
| — публічні IPv4 (ALB має 2, сервер — 1) | $0.005/год кожна |

Beanstalk-середовище коштує **≈ $0.055/год** (≈ $1.3 на добу). Не залишайте його на ніч.

## Типові помилки

| Симптом | Причина / що зробити |
|---|---|
| `beanstalk/`: `no matching EC2 VPC found` | Не застосовано `topic-03-vpc` |
| Звіт у `reports/` не з'явився | Файл завантажено не в `incoming/` або не з розширенням `.csv`. Подивіться логи: `aws logs tail /aws/lambda/goit-orders --since 10m --profile admin` |
| Середовище в стані **Degraded/Severe**, сторінка віддає 502 | Застосунок не стартував. Що саме сталося, видно у вкладці **Logs → Request logs → Last 100 lines** або в CloudWatch у групі `/aws/elasticbeanstalk/goit-app-env/var/log/web.stdout.log` |
| Після `update-environment`: `WSGIPath refers to a file that does not exist` | У zip потрапила папка `app/` замість її вмісту. Пакуйте командою `(cd app && zip -r ../v2.zip .)` |
| `create-application-version`: `Application Version v2 already exists` | Мітки версій унікальні. Дайте нову: `v3`, `v4`… |
