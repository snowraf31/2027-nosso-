#!/usr/bin/env bash
# Aplica as migrations e os seeds do Tabletop num Postgres limpo e roda os testes do banco.
# Uso: PGHOST=... PGPORT=... PGUSER=... PGPASSWORD=... bash scripts/ci/banco.sh
# Cria e apaga o banco "tabletop_ci" (ou $BANCO_TESTE). Nunca aponte para o banco do restaurante.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
DB="${BANCO_TESTE:-tabletop_ci}"

case "${PGHOST:-localhost}" in
  *supabase.co*|*supabase.com*|*pooler.supabase*)
    echo "Recusado: PGHOST aponta para o Supabase. Use um Postgres local ou do CI." >&2
    exit 2 ;;
esac

psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists \"$DB\"" -c "create database \"$DB\""

rodar() {
  echo "-> $1"
  psql -v ON_ERROR_STOP=1 -q -X -d "$DB" -f "$1"
}

rodar scripts/ci/supabase_stubs.sql
for f in supabase/migrations/*.sql; do rodar "$f"; done
for f in supabase/seed.sql supabase/seed_experience.sql supabase/seed_blogs.sql; do
  if [ -f "$f" ]; then rodar "$f"; fi
done

shopt -s nullglob
testes=(supabase/tests/*.sql)
if [ ${#testes[@]} -eq 0 ]; then
  echo "Nenhum teste em supabase/tests/ (só migrations e seeds foram conferidos)."
fi
for f in "${testes[@]}"; do rodar "$f"; done

echo "Banco: ok (${#testes[@]} arquivo(s) de teste)."
