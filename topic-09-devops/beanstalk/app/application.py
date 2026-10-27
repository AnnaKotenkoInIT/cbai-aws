"""Вебзастосунок для Elastic Beanstalk: показує версію коду і сервер, який відповів."""

import pathlib
import urllib.request

from flask import Flask

# Змініть на "2" перед розгортанням нової версії (крок 3 у README)
VERSION = "1"

# Платформа Python у Beanstalk шукає в application.py об'єкт з ім'ям application
application = Flask(__name__)


def metadata(path):
    """Читає метадані EC2 через IMDSv2. Локально метаданих немає — повертає «—»."""
    try:
        token_request = urllib.request.Request(
            "http://169.254.169.254/latest/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
        )
        token = urllib.request.urlopen(token_request, timeout=1).read().decode()
        request = urllib.request.Request(
            f"http://169.254.169.254/latest/meta-data/{path}",
            headers={"X-aws-ec2-metadata-token": token},
        )
        return urllib.request.urlopen(request, timeout=1).read().decode()
    except OSError:
        return "—"


INSTANCE_ID = metadata("instance-id")
ZONE = metadata("placement/availability-zone")

# build.txt пише команда з .ebextensions під час розгортання
build_file = pathlib.Path(__file__).with_name("build.txt")
BUILT = build_file.read_text().strip() if build_file.exists() else "локально"

PAGE = """<!doctype html>
<html lang="uk">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>GoIT · Тема 9 · Elastic Beanstalk</title>
  <style>
    body {{ margin: 0; min-height: 100vh; display: grid; place-items: center;
           font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0; }}
    main {{ text-align: center; padding: 16px; }}
    h1 {{ font-size: 1rem; font-weight: 500; color: #94a3b8; margin: 0 0 12px; }}
    .version {{ font-size: clamp(2.5rem, 12vw, 5rem); color: #22c55e; margin: 0 0 24px; }}
    dl {{ display: grid; grid-template-columns: auto auto; gap: 6px 16px; justify-content: center; margin: 0; }}
    dt {{ color: #94a3b8; text-align: right; }}
    dd {{ margin: 0; text-align: left; font-family: ui-monospace, monospace; }}
  </style>
</head>
<body>
  <main>
    <h1>GoIT · Тема 9 · AWS Elastic Beanstalk</h1>
    <p class="version">Версія {version}</p>
    <dl>
      <dt>Instance</dt><dd>{instance}</dd>
      <dt>Availability Zone</dt><dd>{zone}</dd>
      <dt>Зібрано (.ebextensions)</dt><dd>{built}</dd>
    </dl>
  </main>
</body>
</html>
"""


@application.route("/")
def index():
    return PAGE.format(version=VERSION, instance=INSTANCE_ID, zone=ZONE, built=BUILT)


if __name__ == "__main__":
    application.run(port=8000)
