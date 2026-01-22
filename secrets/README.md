# Secrets Directory

Do not commit any secrets in this directory.

Expected files:
- `jwt.hex` (Engine API JWT secret)
- `validator-keys/` (keystore JSON files)
- `validator-passwords/` (password files for each keystore)

Use the scripts in `scripts/` to generate these files.
