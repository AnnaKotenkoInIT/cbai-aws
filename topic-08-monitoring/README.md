# Тема 8. Моніторинг та аналітика в AWS: CloudWatch, CloudTrail, Config

Terraform-версія практики з теми 8. Три сервіси — три папки, кожна зі своїм `terraform apply`:

| Папка | Що створює | Слайд |
|---|---|---|
| `cloudwatch/` | Сервер з **агентом CloudWatch**, лог-групу, метрику з логів, алярм на CPU з листом, дашборд | Практика CloudWatch |
| `cloudtrail/` | **Trail**, що пише журнал дій у S3 і CloudWatch Logs, та алярм на зміни security groups | Практика CloudTrail |
| `config/` | **AWS Config**: запис налаштувань security groups і бакетів S3 та два готові правила | AWS Config (демо) |

Три сервіси відповідають на три різні запитання:

| Сервіс | Аналогія | Запитання |
|---|---|---|
| CloudWatch | датчики диму й температури | Як почуваються ресурси? |
| CloudTrail | камери й журнал на вахті | Хто, коли і що зробив? |
| Config | інспектор з архівом креслень | Чи все налаштовано за правилами? |

Наприкінці практики всі три спрацюють на одну подію: хтось відкриває SSH для всього інтернету. Config позначає цю security group як порушення, CloudTrail показує, хто її відкрив, а CloudWatch надсилає лист.

## Передумови

- Профіль `admin` з гайду: `aws sts get-caller-identity --profile admin`.
- **Застосована тема 3** (`topic-03-vpc`): сервер з `cloudwatch/` і демо security group живуть у її мережі.
- Email для сповіщень. Без нього алярми спрацюють, але листів не буде.

## 1. CloudWatch: метрики, логи, алярм, дашборд

```bash
cd topic-08-monitoring/cloudwatch
echo 'alert_email = "you@example.com"' > terraform.tfvars    # ваш email
terraform init
terraform apply      # ~1 хв
```

Прийде лист **AWS Notification - Subscription Confirmation**. Натисніть у ньому **Confirm subscription**, інакше SNS не надсилатиме алярми.

Ще ~1 хв після `apply` сервер встановлює Apache й агент CloudWatch (`user-data.sh`).

### Логи

Згенеруйте трафік, зокрема запити на неіснуючі сторінки:

```bash
U=$(terraform output -raw web_url)
for i in $(seq 20); do curl -s -o /dev/null $U/; curl -s -o /dev/null $U/missing; curl -s -o /dev/null $U/admin.php; done

# Рядки access log Apache в CloudWatch, наживо (вихід — Ctrl+C)
aws logs tail $(terraform output -raw log_group) --follow --profile admin
```

Агент на сервері читає `/var/log/httpd/access_log` і за кілька секунд пересилає кожен рядок у лог-групу `/goit-monitor/access`. Terraform створює цю групу з **retention 7 днів**. Без retention логи зберігаються вічно, і за них доводиться платити роками.

**Logs Insights**: CloudWatch → **Logs Insights** → **Saved queries** → `goit-monitor/404-by-path` → **Run query**. Запит показує, які неіснуючі сторінки запитували найчастіше. Мова запитів схожа на SQL: `parse` розбирає рядок на поля, далі йдуть `filter`, `stats` і `sort`.

### Метрики

CloudWatch → **Metrics** → **All metrics**:
- **EC2 → Per-Instance Metrics → CPUUtilization**: стандартна метрика, яку EC2 шле без жодних налаштувань. Завдяки detailed monitoring вона приходить щохвилини, а не раз на 5 хвилин.
- **Пам'яті серед метрик EC2 немає.** Гіпервізор бачить процесор і мережу, але не те, що всередині операційної системи. Метрику `mem_used_percent` у розділі **CWAgent** надсилає агент.
- **GoIT/Web → NotFound**: метрика з логів. Metric filter перетворює кожен рядок зі статусом 404 на +1.

Усе разом показує дашборд: `terraform output -raw dashboard_url`.

### Алярм

Навантажте CPU на 5 хвилин через Session Manager (два процеси `yes` займають обидва ядра t3.micro):

```bash
aws ssm send-command --profile admin --document-name AWS-RunShellScript \
  --targets Key=tag:Name,Values=goit-monitor \
  --parameters 'commands=["for c in 1 2; do timeout 300 yes > /dev/null & done"]'

aws cloudwatch describe-alarms --profile admin --alarm-names goit-monitor-cpu-high \
  --query 'MetricAlarms[0].[StateValue,StateReason]' --output text
```

За 3–4 хвилини алярм перейде в стан **ALARM** і прийде лист. Коли навантаження скінчиться, алярм повернеться в **OK** і надішле ще один лист. Поріг можна змінити: `terraform apply -var cpu_threshold=30`.

## 2. CloudTrail: хто, коли і що зробив

Навіть без trail-а CloudTrail зберігає **Event history** за останні 90 днів. Наприклад, видно, хто запустив сервер у практиці CloudWatch:

```bash
aws cloudtrail lookup-events --profile admin --max-results 5 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --query 'Events[].[EventTime,Username,EventName]' --output table
```

Щоб зберігати журнал довше за 90 днів і будувати по ньому алярми, потрібен trail:

```bash
cd ../cloudtrail
echo 'alert_email = "you@example.com"' > terraform.tfvars
terraform init
terraform apply      # ~30 с
```

Підтвердьте підписку в листі. Trail записує management events з усіх регіонів. Перша копія таких подій в акаунті безкоштовна. Terraform також вмикає **log file validation**: щогодини CloudTrail підписує дайджест журналів, тому підробку записів заднім числом буде видно.

Схема слайда «Принцип роботи AWS CloudTrail» у коді:

| Крок | Ресурс |
|---|---|
| Capture | `aws_cloudtrail.main` |
| Store | бакет S3 + лог-група `/goit-trail/events` |
| Act | metric filter на зміни security groups → алярм → лист |
| Review | Event history і збережений запит Logs Insights |

**Демо.** Відкрийте SSH для всього інтернету, як це зробив би зловмисник або неуважний колега. Security group залиште: вона знадобиться в частині 3.

```bash
VPC=$(aws ec2 describe-vpcs --profile admin --filters Name=tag:Name,Values=goit-vpc --query 'Vpcs[0].VpcId' --output text)
SG=$(aws ec2 create-security-group --profile admin --group-name goit-demo-open-ssh \
  --description "Topic 8 demo: SSH open to the world" --vpc-id $VPC --query GroupId --output text)
aws ec2 authorize-security-group-ingress --profile admin --group-id $SG --protocol tcp --port 22 --cidr 0.0.0.0/0
```

Що буде далі:
- За 1–2 хвилини алярм `goit-trail-sg-changes` перейде в **ALARM** і прийде лист.
- **Хто це зробив**: CloudWatch → Logs Insights → Saved queries → `goit-trail/who-changed-security-groups`. Видно ARN користувача, IP та ID security group.
- Те саме в консолі: **CloudTrail → Event history**, фільтр **Event name = AuthorizeSecurityGroupIngress**. У JSON події видно, хто (`userIdentity`), звідки (`sourceIPAddress`) і що саме (`requestParameters`).
- Файли журналу CloudTrail кладе в S3 приблизно раз на 5 хвилин:

```bash
B=$(terraform output -raw bucket_name)
aws s3 ls s3://$B --recursive --profile admin | tail -n 3
KEY=$(aws s3 ls s3://$B --recursive --profile admin | grep '/CloudTrail/' | tail -n 1 | awk '{print $4}')
aws s3 cp s3://$B/$KEY - --profile admin | gunzip | python3 -m json.tool | head -n 40
```

## 3. AWS Config: чи все за правилами

```bash
cd ../config
terraform init
terraform apply      # ~1 хв
```

Config записує налаштування лише security groups і бакетів S3. Він бере гроші за кожен записаний стан ресурсу, тому в «балакучих» акаунтах кількість типів ресурсів обмежують. Правила:
- `goit-config-restricted-ssh`: SSH (порт 22) не відкритий для `0.0.0.0/0`;
- `goit-config-s3-no-public-access`: у бакета ввімкнено Block Public Access.

Перша перевірка займає кілька хвилин:

```bash
aws configservice describe-compliance-by-config-rule --profile admin \
  --query 'ComplianceByConfigRules[].[ConfigRuleName,Compliance.ComplianceType]' --output table

aws configservice get-compliance-details-by-config-rule --profile admin \
  --config-rule-name goit-config-restricted-ssh --compliance-types NON_COMPLIANT \
  --query 'EvaluationResults[].EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId' --output text
```

Серед порушників буде `goit-demo-open-ssh` з частини 2. У консолі відкрийте **Config → Rules → goit-config-restricted-ssh**, потім цю security group і **Resource timeline**. На таймлайні є і зміни налаштувань, і події CloudTrail: хто й коли відкрив порт. Інші знайдені порушення — реальні проблеми вашого акаунта.

Виправте порушення, видаливши security group:

```bash
aws ec2 delete-security-group --profile admin --group-id $(aws ec2 describe-security-groups --profile admin \
  --filters Name=group-name,Values=goit-demo-open-ssh --query 'SecurityGroups[0].GroupId' --output text)
```

Config прибере її з порушників, а CloudTrail зафіксує `DeleteSecurityGroup`, і алярм з частини 2 надішле ще один лист.

> У регіоні може бути лише один configuration recorder. Якщо Config уже вмикали в консолі, Terraform перезапише recorder і delivery channel з ім'ям `default` своїми налаштуваннями, а `terraform destroy` їх видалить.

## Прибирання — обов'язково після заняття

Папки незалежні, порядок не важливий:

```bash
cd topic-08-monitoring/config && terraform destroy
cd ../cloudtrail && terraform destroy     # видаляє trail і бакет разом з журналами
cd ../cloudwatch && terraform destroy
```

Якщо ви пропустили частину 3, видаліть і демо security group `goit-demo-open-ssh` (команда вище).

## Вартість

| Ресурс | Приблизно |
|---|---|
| EC2 t3.micro + публічна IPv4 | $0.012 + $0.005/год |
| Власні метрики (RAM, 404, зміни SG), detailed monitoring | $0.30 за метрику на місяць, рахується погодинно — копійки |
| CloudWatch Logs | $0.63 за ГБ; перші 5 ГБ на місяць безкоштовні |
| Алярми, дашборд | Безкоштовно: 10 алярмів і 3 дашборди |
| CloudTrail | Перша копія management events безкоштовна; S3 для журналу — копійки |
| AWS Config | $0.003 за записаний стан ресурсу, $0.001 за перевірку правилом |

Заняття, після якого все видалено, коштує **менше $0.10**.

## Типові помилки

| Симптом | Причина / що зробити |
|---|---|
| `cloudwatch/`: `no matching EC2 VPC found` | Не застосовано `topic-03-vpc` |
| Лист з алярмом не прийшов | Не підтверджено підписку або не задано `alert_email`. Перевірка: `aws sns list-subscriptions --profile admin` — `PendingConfirmation` означає, що лист з підтвердженням ще не відкрито |
| Метрики RAM немає | Агент починає роботу ~2 хв після `apply`, ще хвилину йде перша точка. У списку метрик консолі нова метрика з'являється із затримкою |
| Logs Insights нічого не знаходить | Перевірте часовий діапазон угорі праворуч. Свіжі рядки стають доступні для пошуку за 1–2 хвилини |
| `config/`: `MaxNumberOfConfigurationRecordersExceededException` або `MaxNumberOfDeliveryChannelsExceededException` | Config уже вмикали з іншим ім'ям recorder-а. Імена покажуть `describe-configuration-recorders` і `describe-delivery-channels`. Видаліть старі по черзі: `stop-configuration-recorder`, `delete-delivery-channel`, `delete-configuration-recorder` (усі — `aws configservice ... --profile admin`) |
