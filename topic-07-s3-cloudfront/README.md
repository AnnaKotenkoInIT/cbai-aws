# Тема 7. Зберігання та кешування даних в AWS: S3 і CloudFront

Terraform-версія практики з теми 7. Дві практики — дві папки, кожна зі своїм `terraform apply`:

| Папка | Що створює | Слайд |
|---|---|---|
| `s3/` | Приватний бакет **Amazon S3** + файли фронтенду з `s3/site/` | Створення Amazon S3 |
| `cloudfront/` | Дистрибуцію **Amazon CloudFront** перед бакетом | Створення Amazon CloudFront |

```
Браузер ──HTTPS──▶ CloudFront: найближчий edge-сервер, кеш
                       │  OAC: CloudFront підписує запит
                       ▼
                   S3-бакет у Франкфурті: приватний, публічного доступу немає
```

Фронтенд — статична сторінка з трьох файлів: `index.html`, `assets/style.css`, `assets/app.js`. Сторінка показує, **хто її віддав**:
- через CloudFront — edge location, стан кешу (Hit / Miss) і скільки секунд копія лежить у кеші;
- через підписане посилання S3 — лише текст без стилів (чому так — у кроці 1).

## Передумови

- Профіль `admin` з гайду: `aws sts get-caller-identity --profile admin`.
- Тема 3 **не потрібна**: S3 і CloudFront працюють поза VPC.

## 1. S3: бакет і файли сайту

```bash
cd topic-07-s3-cloudfront/s3
terraform init
terraform apply      # кілька секунд

B=$(terraform output -raw bucket_name)
aws s3 ls s3://$B --recursive --profile admin
```

Бакет називається `goit-site-<номер акаунта>`: ім'я бакета має бути унікальним в усьому світі.

Terraform завантажує кожен файл з `site/` як об'єкт, а шлях до файлу стає ключем об'єкта. Папок у S3 насправді немає. `assets/app.js` — це просто ключ зі слешем, а консоль малює з `assets/` папку для зручності.

Кожному файлу Terraform ставить **Content-Type** з мапи `content_types` у `main.tf`. Без нього браузер не показав би сторінку, а запропонував би її завантажити.

Бакет приватний, тож пряма адреса об'єкта не відкривається:

```bash
curl -I $(terraform output -raw object_url)      # HTTP/1.1 403 Forbidden
```

Тимчасовий доступ до одного файлу дає **presigned URL** — посилання з криптографічним підписом і терміном дії:

```bash
aws s3 presign s3://$B/index.html --expires-in 300 --profile admin
```

Відкрийте це посилання в браузері: сторінка буде без стилів. Підпис діє лише на `index.html`, а `style.css` і `app.js` — окремі приватні об'єкти. Через 5 хвилин посилання перестане працювати. Віддати весь сайт — це завдання CloudFront.

У консолі: **S3 → Buckets → goit-site-… → Objects**. На вкладці **Permissions** видно, що **Block public access** увімкнено.

## 2. CloudFront: CDN перед бакетом

```bash
cd ../cloudfront
terraform init
terraform apply      # ~3 хв
terraform output -raw site_url
```

Відкрийте `site_url`. Сторінка покаже **Amazon CloudFront**, edge location і стан кешу.

Terraform створює три ресурси:
1. **Origin Access Control (OAC)**: CloudFront підписує кожен запит до S3.
2. **Дистрибуцію CloudFront**:
   - origin — бакет з кроку 1;
   - HTTPS із сертифікатом `*.cloudfront.net` (запит по HTTP отримує редирект 301);
   - кешування за готовою політикою `Managed-CachingOptimized` (до 24 год);
   - клас `PriceClass_100`: edge-сервери Європи та Північної Америки, найдешевший варіант.
3. **Політику бакета**: читати файли (`s3:GetObject`) дозволено лише сервісу CloudFront і лише для цієї дистрибуції (умова `AWS:SourceArn`).

Пряма адреса S3 і далі дає 403. Відкрити файли можна лише через CloudFront.

### Кеш у дії

```bash
U=$(terraform output -raw site_url)
for i in 1 2 3 4; do curl -sI $U | grep -iE 'x-cache|x-amz-cf-pop|^age'; done
```

- `x-cache: Miss from cloudfront`: копії в кеші не було, CloudFront сходив по файл у S3. Перші кілька запитів можуть бути Miss, бо в локації кілька серверів і кожен заповнює свій кеш.
- `x-cache: Hit from cloudfront`: файл віддано з кешу edge-сервера, до S3 запит не дійшов.
- `age`: скільки секунд копія вже лежить у кеші.
- `x-amz-cf-pop`: edge location. Перші три літери — код аеропорту поруч: FRA — Франкфурт, VIE — Відень, WAW — Варшава.

У консолі: **CloudFront → Distributions** → дистрибуція з описом `goit-site`. На вкладці **Origins** видно бакет і OAC. Розділ **Reports & analytics → Cache statistics** показує частку Hit і Miss із затримкою кілька хвилин.

### Оновлення сайту та інвалідація кешу

1. У `s3/site/index.html` змініть `Версія сайту: 1` на `Версія сайту: 2`.
2. Виконайте `cd ../s3 && terraform apply`: у бакеті тепер нова версія.
3. Оновіть сторінку CloudFront з **Cmd+Shift+R** (Ctrl+F5 у Windows), щоб браузер не взяв її з власного кешу. Сторінка все ще показує «Версія сайту: 1»: edge-сервер тримає старий файл у кеші до 24 годин.
4. Скиньте кеш інвалідацією:

```bash
cd ../cloudfront
aws cloudfront create-invalidation --profile admin \
  --distribution-id $(terraform output -raw distribution_id) --paths "/*"
```

Приблизно за хвилину сторінка покаже «Версія сайту: 2», а кеш знову почнеться з Miss.

> У продакшені до цієї схеми додають власний домен із безкоштовним сертифікатом **AWS Certificate Manager** і **AWS WAF** перед CloudFront: він захищає від ботів і DDoS та обмежує кількість запитів з одного IP.

## Прибирання — обов'язково після заняття

У зворотному порядку:

```bash
cd topic-07-s3-cloudfront/cloudfront && terraform destroy   # ~3 хв: CloudFront спершу вимикає дистрибуцію
cd ../s3 && terraform destroy                                # видаляє бакет разом з файлами
```

Папка `cloudfront/` шукає бакет з `s3/`, тож видаляйте її першою.

## Вартість

| Ресурс | Приблизно |
|---|---|
| S3 Standard (eu-central-1) | $0.0245 за ГБ на місяць; сайт важить ~3 КБ |
| S3 GET-запити | $0.00043 за 1000. CloudFront ходить у S3 лише при Miss |
| CloudFront | Безкоштовно: 1 ТБ трафіку та 10 млн запитів на місяць |
| Інвалідація | Перші 1000 шляхів на місяць безкоштовні, `/*` рахується як один шлях |

Заняття фактично безкоштовне.

## Типові помилки

| Симптом | Причина / що зробити |
|---|---|
| `cloudfront/`: `couldn't find resource` для бакета | Спершу `terraform apply` у `s3/` |
| `s3/`: `Invalid index` на `content_types` | У `site/` з'явився файл нового типу (наприклад `.jpg`). Додайте його розширення в мапу `content_types` у `s3/main.tf` |
| Сторінка без стилів | Відкрито presigned URL або пряму адресу S3. Відкривайте `site_url` |
| CloudFront віддає стару версію сайту | Файл лежить у кеші edge-сервера: зробіть інвалідацію (див. вище) |
| CloudFront повертає XML `AccessDenied` | Такого файлу немає в бакеті: без права `s3:ListBucket` S3 відповідає на відсутній ключ 403, а не 404 |
