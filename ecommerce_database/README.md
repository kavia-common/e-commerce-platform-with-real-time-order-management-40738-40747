# E-commerce Database Migrations

This folder contains PostgreSQL migrations and seed data for the e-commerce platform.

Connection (local defaults):
- Host: localhost
- Port: 5000
- Database: myapp
- User: appuser
- Password: dbuser123

A ready-to-use connection command is also stored in db_connection.txt by startup.sh.

## Files

- migrations/0001_init.sql — Creates tables, constraints, indexes, triggers
- migrations/0002_seed.sql — Seeds users, products, orders, order_items, returns, return_policies, recommendations
- startup.sql — Runs both migration and seed (wrapper)

## How to run with psql

Prerequisites: PostgreSQL running on port 5000 with database/user created (startup.sh in this folder does that automatically in the runtime environment).

1) Using connection string from db_connection.txt:
   - cat db_connection.txt
   - Example:
     psql postgresql://appuser:dbuser123@localhost:5000/myapp

2) Apply migrations (localhost:5000, DB=myapp, user=appuser, pass=dbuser123):

- Run all at once:
  psql postgresql://appuser:dbuser123@localhost:5000/myapp -f startup.sql

- Or run step-by-step:
  psql postgresql://appuser:dbuser123@localhost:5000/myapp -f migrations/0001_init.sql
  psql postgresql://appuser:dbuser123@localhost:5000/myapp -f migrations/0002_seed.sql

3) Verify:
  psql postgresql://appuser:dbuser123@localhost:5000/myapp -c "\\dt"
  psql postgresql://appuser:dbuser123@localhost:5000/myapp -c "SELECT * FROM users LIMIT 5"

4) Troubleshooting:
- Ensure Postgres is available on port 5000 and credentials match the backend DATABASE_URL.
- Regenerate seed data by re-running startup.sql if needed.

## Notes

- Scripts are compatible with the current startup.sh which configures database, user and saves connection details.
- Seed scripts are idempotent where unique constraints exist (ON CONFLICT used where applicable).
- Triggers maintain updated_at and order totals automatically.
