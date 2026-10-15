# Тема 6. Сховища даних в AWS: RDS і DynamoDB

Terraform-версія практики з теми 6. Дві практики — дві папки, кожна зі своїм `terraform apply`:

| Папка | Що створює | Слайд |
|---|---|---|
| `rds/` | PostgreSQL в **Amazon RDS** + таблиці магазину з даними (`seed.sql`) | Створення RDS в AWS |
| `dynamodb/` | Таблицю **DynamoDB** `goit-carts` + кошики покупок (`seed.json`) | Створення Amazon DynamoDB |

Обидві бази — частини одного інтернет-магазину:
- **RDS**: клієнти, товари й замовлення. Таблиці зв'язані зовнішніми ключами, тож дані завжди цілісні, а складні запити пишуться через `JOIN`.
- **DynamoDB**: кошики, тобто дані, що часто змінюються. Доступ іде за ключем «клієнт + товар», а набір полів у кожного елемента може бути свій.

Наповнення відбувається саме під час `terraform apply`, окремих кроків не треба.

## Передумови

- Профіль `admin` з гайду: `aws sts get-caller-identity --profile admin`.
- Для RDS:
  - **застосована тема 3** (`topic-03-vpc`): база запускається в її публічних підмережах;
  - **запущений Docker** (Docker Desktop): Terraform наповнює базу через `psql` у контейнері, і через нього ж ви підключаєтеся до бази.
- Для DynamoDB нічого з цього не потрібно: таблиця живе на рівні регіону, без VPC.

## 1. RDS: PostgreSQL

```bash
cd topic-06-databases/rds

# Ваш публічний IP — лише з нього буде відкрито порт бази 5432
echo "my_ip_cidr = \"$(curl -s https://checkip.amazonaws.com)/32\"" > terraform.tfvars

terraform init
terraform apply      # ~5 хв
```

`terraform apply` робить три речі:
1. Генерує пароль і створює базу `shop`, адміністратор — `goit`.
2. Створює Security Group з портом 5432, відкритим лише для вашого IP.
3. Запускає `seed.sql`, який створює таблиці `customers`, `products`, `orders` і заповнює їх даними.

Підключення до бази:

```bash
export PGPASSWORD=$(terraform output -raw db_password)
docker run --rm -it -e PGPASSWORD postgres:18-alpine \
  psql -h $(terraform output -raw endpoint) -U goit -d shop
```

Запити, які варто спробувати в `psql`:

```sql
\dt
SELECT * FROM customers;

-- Хто що купив: JOIN трьох таблиць
SELECT c.name AS customer, p.name AS product, o.quantity, p.price * o.quantity AS total
FROM orders o
JOIN customers c ON c.id = o.customer_id
JOIN products p ON p.id = o.product_id
ORDER BY o.created_at;

-- Скільки витратив кожен клієнт (LEFT JOIN покаже й тих, хто нічого не купив)
SELECT c.name, count(o.id) AS orders, coalesce(sum(p.price * o.quantity), 0) AS spent
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.id
LEFT JOIN products p ON p.id = o.product_id
GROUP BY c.name
ORDER BY spent DESC;

-- Цілісність даних: замовлення для неіснуючого клієнта база не прийме
INSERT INTO orders (customer_id, product_id, quantity) VALUES (99, 1, 1);
```

Вихід з `psql`: `\q`.

Змінили `seed.sql`? Наступний `terraform apply` сам перезаллє дані. Повернути початкові дані без змін у файлі можна так: `terraform apply -replace=terraform_data.seed`.

> Базу відкрито в інтернет лише для вашого IP, щоб підключитися з ноутбука. У продакшені RDS кладуть у приватні підмережі, і застосунок ходить до неї зсередини VPC.

## 2. DynamoDB: кошики покупок

```bash
cd topic-06-databases/dynamodb
terraform init
terraform apply      # кілька секунд
```

У таблиці `goit-carts` складений ключ:
- `customer_id` — partition key;
- `product_id` — sort key.

Елементи з `seed.json` записані у форматі DynamoDB JSON, де біля кожного значення вказано його тип (`S` — рядок, `N` — число, `M` — вкладений документ). Подивіться, як цей формат виглядає в консолі: **DynamoDB → Tables → goit-carts → Explore table items**.

```bash
# Один елемент за повним ключем
aws dynamodb get-item --profile admin --table-name goit-carts \
  --key '{"customer_id":{"N":"1"},"product_id":{"N":"4"}}'

# Увесь кошик клієнта 1: Query за partition key
aws dynamodb query --profile admin --table-name goit-carts \
  --key-condition-expression "customer_id = :c" \
  --expression-attribute-values '{":c":{"N":"1"}}'

# Додати товар у кошик клієнта 3
aws dynamodb put-item --profile admin --table-name goit-carts \
  --item '{"customer_id":{"N":"3"},"product_id":{"N":"2"},"name":{"S":"Навушники"},"price":{"N":"2499"},"quantity":{"N":"1"}}'

# Збільшити кількість на 1
aws dynamodb update-item --profile admin --table-name goit-carts \
  --key '{"customer_id":{"N":"3"},"product_id":{"N":"2"}}' \
  --update-expression "SET quantity = quantity + :one" \
  --expression-attribute-values '{":one":{"N":"1"}}' --return-values UPDATED_NEW

# Уся таблиця: Scan читає кожен елемент, тому на великих таблицях він повільний і дорогий
aws dynamodb scan --profile admin --table-name goit-carts \
  --query 'Items[].[customer_id.N, product_id.N, name.S, quantity.N]' --output text
```

Порівняйте з RDS. Тут немає `JOIN` і схеми: у ноутбука в кошику є `options` і `coupon`, а в мишки їх немає. Зате елемент за ключем читається за мілісекунди за будь-якого обсягу таблиці.

Якщо ви змінили елементи з `seed.json` вручну, наступний `terraform apply` поверне їх до вмісту файлу. Додані вручну елементи Terraform не чіпає.

## Прибирання — обов'язково після заняття

```bash
cd topic-06-databases/rds && terraform destroy        # ~2 хв
cd ../dynamodb && terraform destroy
```

Тему 3 (`topic-03-vpc`) видаляйте, лише якщо мережа більше не потрібна.

## Вартість

| Ресурс | Приблизно |
|---|---|
| RDS db.t4g.micro (PostgreSQL, Single-AZ) | $0.019/год |
| RDS сховище gp2, 20 ГБ | $2.74 на місяць ≈ $0.004/год |
| Публічна IPv4 бази | $0.005/год |
| DynamoDB on-demand | копійки за запити; перші 25 ГБ сховища безкоштовні |

Заняття, після якого все видалено, коштує **менше $0.20**. RDS, забута на добу, — близько $0.70.

## Типові помилки

| Симптом | Причина / що зробити |
|---|---|
| `no matching EC2 VPC found` у `rds/` | Не застосовано `topic-03-vpc` |
| Terraform питає `var.my_ip_cidr` | Не створено `terraform.tfvars` (крок 1 RDS) |
| `terraform_data.seed`: `failed to connect to the docker API` | Запустіть Docker Desktop і повторіть `terraform apply`: база вже є, тож виконається лише наповнення |
| `psql`: `timeout expired` / `Connection timed out` | Змінився ваш IP (інший Wi‑Fi чи VPN): оновіть `terraform.tfvars` і виконайте `terraform apply` |
| `psql`: `password authentication failed` | Не виконано `export PGPASSWORD=...` з `terraform output -raw db_password` |
| `ResourceNotFoundException` у командах `aws dynamodb` | Не той регіон: таблиця в `eu-central-1` |
