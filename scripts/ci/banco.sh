#!/usr/bin/env bash
# Aplica as migrations e os seeds do Tabletop num Postgres limpo e roda os testes do banco.
# Uso: PGHOST=... PGPORT=... PGUSER=... PGPASSWORD=... bash scripts/ci/banco.sh
# Cria e apaga o banco "tabletop_ci" (ou $BANCO_TESTE). Nunca aponte para o banco do restaurante.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
DB="${BANCO_TESTE:-tabletop_ci}"

# Só roda contra Postgres local ou do CI: nunca contra o banco do restaurante.
[[ "$DB" =~ ^[a-z_][a-z0-9_]*$ ]] || { echo "Recusado: BANCO_TESTE inválido." >&2; exit 2; }
[ -z "${PGHOSTADDR:-}" ] && [ -z "${PGSERVICE:-}" ] || { echo "Recusado: PGHOSTADDR/PGSERVICE não são aceitos." >&2; exit 2; }
case "${PGHOST:-localhost}" in
  localhost|127.0.0.1|::1|/*) ;;
  *) echo "Recusado: PGHOST precisa ser localhost ou socket local." >&2; exit 2 ;;
esac

psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists \"$DB\"" -c "create database \"$DB\""

rodar() {
  echo "-> $1"
  psql -v ON_ERROR_STOP=1 -q -X -d "$DB" -f "$1"
}

rodar scripts/ci/supabase_stubs.sql
for f in supabase/migrations/*.sql; do rodar "$f"; done
# Seeds: seed.sql primeiro, depois os outros seed_*.sql em ordem alfabética.
if [ -f supabase/seed.sql ]; then rodar supabase/seed.sql; fi
for f in supabase/seed_*.sql; do
  if [ -f "$f" ]; then rodar "$f"; fi
done

shopt -s nullglob
testes=(supabase/tests/*.sql)
# Com set -u, o bash 3.2 (macOS) acusa "unbound variable" ao expandir um array vazio:
# o laço só roda quando há testes.
if [ ${#testes[@]} -eq 0 ]; then
  echo "Nenhum teste em supabase/tests/ (só migrations e seeds foram conferidos)."
else
  for f in "${testes[@]}"; do rodar "$f"; done
fi

echo "Banco: ok (${#testes[@]} arquivo(s) de teste)."
