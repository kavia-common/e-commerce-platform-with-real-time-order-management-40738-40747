-- startup.sql: Convenience script to run initial migration and seed
\set ON_ERROR_STOP on

-- Create schema objects
\i migrations/0001_init.sql

-- Seed data
\i migrations/0002_seed.sql

-- Show a quick summary
SELECT
  (SELECT COUNT(*) FROM users) AS users_count,
  (SELECT COUNT(*) FROM products) AS products_count,
  (SELECT COUNT(*) FROM orders) AS orders_count,
  (SELECT COUNT(*) FROM order_items) AS order_items_count,
  (SELECT COUNT(*) FROM returns) AS returns_count,
  (SELECT COUNT(*) FROM return_policies) AS return_policies_count,
  (SELECT COUNT(*) FROM recommendations) AS recommendations_count;
