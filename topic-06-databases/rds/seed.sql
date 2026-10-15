-- Інтернет-магазин: клієнти, товари й замовлення у зв'язаних таблицях.
-- Скрипт можна запускати повторно: таблиці створюються заново.

SET client_min_messages = warning;

DROP TABLE IF EXISTS orders, products, customers;

CREATE TABLE customers (
  id    SERIAL PRIMARY KEY,
  name  TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  city  TEXT NOT NULL
);

CREATE TABLE products (
  id    SERIAL PRIMARY KEY,
  name  TEXT NOT NULL,
  price NUMERIC(10, 2) NOT NULL CHECK (price > 0)
);

-- REFERENCES — зовнішні ключі: замовлення не може посилатися на неіснуючого клієнта чи товар
CREATE TABLE orders (
  id          SERIAL PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES customers (id),
  product_id  INT NOT NULL REFERENCES products (id),
  quantity    INT NOT NULL CHECK (quantity > 0),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO customers (name, email, city) VALUES
  ('Олена Коваль',  'olena@example.com',  'Київ'),
  ('Андрій Шевчук', 'andrii@example.com', 'Львів'),
  ('Марія Бондар',  'maria@example.com',  'Одеса'),
  ('Тарас Мельник', 'taras@example.com',  'Харків');

INSERT INTO products (name, price) VALUES
  ('Ноутбук',    32999.00),
  ('Навушники',   2499.00),
  ('Клавіатура',  1899.00),
  ('Монітор',     8999.00),
  ('Мишка',        799.00);

INSERT INTO orders (customer_id, product_id, quantity, created_at) VALUES
  (1, 1, 1, '2026-10-01 10:15+03'),
  (1, 2, 2, '2026-10-01 10:15+03'),
  (2, 4, 1, '2026-10-03 18:40+03'),
  (2, 3, 1, '2026-10-05 09:05+03'),
  (3, 5, 3, '2026-10-07 21:30+03'),
  (3, 2, 1, '2026-10-07 21:30+03'),
  (1, 5, 1, '2026-10-10 12:00+03');
