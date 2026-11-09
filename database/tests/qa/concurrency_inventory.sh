#!/bin/sh
# QA PLAT-613/614: varias sesiones descuentan stock del mismo lote a la vez; el saldo nunca debe quedar
# negativo ni perder movimientos. Se ejecuta DENTRO del contenedor db (base con datos demo):
#   docker compose --env-file .env.docker exec -T db sh /repo/database/tests/qa/concurrency_inventory.sh
set -eu
export PGPASSWORD="${POSTGRES_PASSWORD:?}"
P="psql -h localhost -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -tA"
LOT_CODE="${LOT_CODE:-DEMO-GEI-2026-01}"
STEP=30
WORKERS=6

lot=$($P -c "select id from public.product_lot where lot_code = '$LOT_CODE'")
[ -n "$lot" ] || { echo "No existe el lote $LOT_CODE (carga database/seeds/demo/seed_demo.sql)."; exit 2; }
before=$($P -c "select coalesce(sum(quantity_delta),0) from public.inventory_movement where product_lot_id = $lot")
expected_ok=$(python3 -c "print(min($WORKERS, int($before // $STEP)))")
echo "Lote $LOT_CODE: saldo inicial $before; $WORKERS descuentos concurrentes de $STEP; deben pasar $expected_ok."

rm -f /tmp/qa_inv_*
i=1
while [ "$i" -le "$WORKERS" ]; do
  ( $P -c "insert into public.inventory_movement(product_lot_id, quantity_delta, movement_type) values ($lot, -$STEP, 'adjustment')" >/dev/null 2>&1 \
      && echo ok > /tmp/qa_inv_$i || echo fail > /tmp/qa_inv_$i ) &
  i=$((i + 1))
done
wait

ok=$(cat /tmp/qa_inv_* | grep -c '^ok$' || true)
after=$($P -c "select coalesce(sum(quantity_delta),0) from public.inventory_movement where product_lot_id = $lot")
rm -f /tmp/qa_inv_*
# Se restituye el saldo para dejar los datos demo como estaban.
if [ "$ok" -gt 0 ]; then
  $P -c "insert into public.inventory_movement(product_lot_id, quantity_delta, movement_type) values ($lot, $((ok * STEP)), 'adjustment')" >/dev/null
fi

fail=0
[ "$ok" -eq "$expected_ok" ] || { echo "FALLO: pasaron $ok descuentos, se esperaban $expected_ok."; fail=1; }
python3 - <<PY || fail=1
b, a, ok, s = $before, $after, $ok, $STEP
assert a >= 0, f"saldo negativo: {a}"
assert a == b - ok * s, f"saldo inconsistente: {a} != {b} - {ok}*{s}"
print(f"Saldo final {a} = {b} - {ok}*{s}: consistente y no negativo.")
PY
[ "$fail" -eq 0 ] && echo "OK: la concurrencia respeta el stock." || exit 1
