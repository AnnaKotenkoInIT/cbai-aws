"""Рахує суми з CSV-файлу замовлень і кладе звіт у JSON поруч, у reports/."""

import csv
import io
import json
import urllib.parse

import boto3

# Код поза handler виконується один раз, під час холодного старту.
# Наступні виклики в тому самому контейнері перевикористовують цей клієнт.
s3 = boto3.client("s3")


def handler(event, context):
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        body = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode("utf-8")
        rows = list(csv.DictReader(io.StringIO(body)))

        # Файл без колонок product, qty, price впаде тут з KeyError — і потрапить у чергу failed
        by_product = {}
        for row in rows:
            amount = int(row["qty"]) * float(row["price"])
            by_product[row["product"]] = round(by_product.get(row["product"], 0) + amount, 2)

        report = {
            "source": key,
            "orders": len(rows),
            "total": round(sum(by_product.values()), 2),
            "by_product": by_product,
        }
        report_key = "reports/" + key.removeprefix("incoming/").removesuffix(".csv") + ".json"
        s3.put_object(
            Bucket=bucket,
            Key=report_key,
            Body=json.dumps(report, ensure_ascii=False, indent=2),
            ContentType="application/json",
        )

        # print потрапляє в CloudWatch Logs
        print(json.dumps({"source": key, "report": report_key, "total": report["total"]}))
