// Скрипт завантажився — отже, сторінку віддав не підписаний URL S3, а CloudFront (або вона відкрита локально)
const where = document.getElementById('where');
document.getElementById('hint').remove();
where.textContent = 'Без CDN · локально';

// Питаємо заголовки цієї ж сторінки: який edge-сервер CloudFront її віддав і чи була вона в кеші
fetch(location.href, { method: 'HEAD' }).then((res) => {
  const pop = res.headers.get('x-amz-cf-pop');
  if (!pop) return;

  where.textContent = 'Amazon CloudFront';
  const rows = {
    'Edge location': pop, // перші три літери — код найближчого аеропорту: FRA — Франкфурт, WAW — Варшава
    'Кеш': res.headers.get('x-cache'),
    'У кеші вже': `${res.headers.get('age') ?? 0} с`,
  };
  const details = document.getElementById('details');
  for (const [name, value] of Object.entries(rows)) {
    details.append(
      Object.assign(document.createElement('dt'), { textContent: name }),
      Object.assign(document.createElement('dd'), { textContent: value }),
    );
  }
});
