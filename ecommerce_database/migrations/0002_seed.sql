-- 0002_seed.sql: Seed data for e-commerce platform

-- Users
INSERT INTO users (email, full_name, password_hash)
VALUES
  ('alice@example.com', 'Alice Johnson', 'hash_alice'),
  ('bob@example.com', 'Bob Smith', 'hash_bob'),
  ('carol@example.com', 'Carol Lee', 'hash_carol')
ON CONFLICT (email) DO NOTHING;

-- Products
INSERT INTO products (sku, name, description, price_cents, currency_code, in_stock, inventory_count)
VALUES
  ('SKU-1001', 'Wireless Headphones', 'Noise-cancelling over-ear headphones', 12999, 'USD', TRUE, 50),
  ('SKU-1002', 'Smart Watch', 'Water-resistant smartwatch with heart-rate monitor', 19999, 'USD', TRUE, 35),
  ('SKU-1003', 'USB-C Charger', 'Fast charging 65W USB-C wall charger', 3999, 'USD', TRUE, 120),
  ('SKU-1004', 'Bluetooth Speaker', 'Portable speaker with deep bass', 8999, 'USD', TRUE, 60)
ON CONFLICT (sku) DO NOTHING;

-- Return Policies
INSERT INTO return_policies (product_id, policy_name, description, days_allowed, restocking_fee_percent)
SELECT p.id, 'Standard 30-Day', 'Returns accepted within 30 days in original condition.', 30, 0.00
FROM products p
WHERE p.sku IN ('SKU-1001','SKU-1002','SKU-1003','SKU-1004')
ON CONFLICT DO NOTHING;

-- Create a sample order for Alice with two items
WITH u AS (
  SELECT id AS user_id FROM users WHERE email = 'alice@example.com'
),
o AS (
  INSERT INTO orders (user_id, status, currency_code)
  SELECT user_id, 'paid', 'USD' FROM u
  RETURNING id
)
INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents, currency_code)
SELECT o.id, p.id,
       CASE WHEN p.sku = 'SKU-1003' THEN 2 ELSE 1 END AS quantity,
       p.price_cents, 'USD'
FROM o
JOIN products p ON p.sku IN ('SKU-1001','SKU-1003');

-- Create a shipped order for Bob with one speaker
WITH u AS (
  SELECT id AS user_id FROM users WHERE email = 'bob@example.com'
),
o AS (
  INSERT INTO orders (user_id, status, currency_code)
  SELECT user_id, 'shipped', 'USD' FROM u
  RETURNING id
)
INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents, currency_code)
SELECT o.id, p.id, 1, p.price_cents, 'USD'
FROM o
JOIN products p ON p.sku = 'SKU-1004';

-- Recommendations
INSERT INTO recommendations (user_id, product_id, score, reason)
SELECT u.id, p.id, 0.875, 'Similar customers also bought'
FROM users u, products p
WHERE u.email = 'alice@example.com' AND p.sku = 'SKU-1002'
ON CONFLICT DO NOTHING;

INSERT INTO recommendations (user_id, product_id, score, reason)
SELECT u.id, p.id, 0.652, 'Frequently bought together'
FROM users u, products p
WHERE u.email = 'bob@example.com' AND p.sku = 'SKU-1003'
ON CONFLICT DO NOTHING;

-- Sample return request for Alice (for USB-C Charger item)
WITH oi AS (
  SELECT oi.id, oi.order_id, o.user_id
  FROM order_items oi
  JOIN orders o ON o.id = oi.order_id
  JOIN products p ON p.id = oi.product_id
  JOIN users u ON u.id = o.user_id
  WHERE u.email = 'alice@example.com' AND p.sku = 'SKU-1003'
  LIMIT 1
)
INSERT INTO returns (order_id, order_item_id, user_id, reason, status, refund_cents)
SELECT order_id, id, user_id, 'Changed mind', 'requested', 3999
FROM oi
ON CONFLICT DO NOTHING;
