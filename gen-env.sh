#!/bin/sh
# Creates .env from .env.example with freshly generated secrets.
# ANTHROPIC_API_KEY (and PUBLIC_URL, if it differs) still have to be filled in by hand.
set -eu
cd "$(dirname "$0")"

if [ -e .env ]; then
  echo ".env already exists; remove it first to regenerate (changing LITELLM_SALT_KEY breaks stored keys)." >&2
  exit 1
fi

secret() { openssl rand -hex "${1:-32}"; } # hex: safe in connection URLs

cp .env.example .env
set_var() { sed -i "s|^$1=.*|$1=$2|" .env; }

set_var POSTGRES_PASSWORD "$(secret)"
set_var S3_SECRET_KEY "$(secret)"
set_var JWT_SECRET "$(secret 48)"
set_var SEED_PASSWORD "$(secret 12)"
set_var LITELLM_MASTER_KEY "sk-$(secret)"
set_var LITELLM_SALT_KEY "$(secret)"
set_var LITELLM_BACKEND_KEY "sk-$(secret)"

chmod 600 .env
echo "Wrote .env. Still to fill in: ANTHROPIC_API_KEY (check PUBLIC_URL too)."
