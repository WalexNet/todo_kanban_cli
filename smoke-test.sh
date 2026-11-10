#!/usr/bin/env bash
# Pruebas funcionales en un directorio temporal: no toca ~/.local/share/todo.
set -euo pipefail

BIN="${1:-./src/todo}"
BIN="$(realpath "$BIN")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_DATA_HOME="$TMP"
export NO_COLOR=1

"$BIN" add 'Revisar OSPF del laboratorio' alta Redes --due 2026-12-01
"$BIN" add 'Estudiar Lazarus' media Formación
"$BIN" add 'Organizar notas' baja Personal
"$BIN" add 'Actualizar VPS' alta Sistemas

"$BIN" ls creada | grep -q 'Total mostrado: 4'
"$BIN" ls | grep -q 'Total mostrado: 4'
"$BIN" ls ok | grep -q 'Total mostrado: 0'
"$BIN" show 1 | grep -q 'Estado:     Creada'
"$BIN" show 1 | grep -q 'Vence:      2026-12-01'
"$BIN" show 2 | grep -q 'Categoria:  Formación'
"$BIN" board | grep -q 'TABLERO KANBAN'
"$BIN" board --cat Redes | grep -q 'Revisar OSPF'
"$BIN" cats | grep -q 'Redes'

"$BIN" 1 plan
"$BIN" 1 start
"$BIN" ls trabajo | grep -q 'Total mostrado: 1'
"$BIN" show 1 | grep -q 'Estado:     En trabajo'
"$BIN" show 1 | grep -q 'Inicio:'
"$BIN" move 2 trabajo
"$BIN" move 3 trabajo
if "$BIN" 4 start 2>/dev/null; then
  echo 'ERROR: se ha permitido superar el limite WIP.' >&2
  exit 1
fi
"$BIN" ls trabajo | grep -q 'Total mostrado: 3'
"$BIN" 1 ok
"$BIN" ls ok | grep -q 'Revisar OSPF'
"$BIN" 4 start
"$BIN" 1 reopen
"$BIN" show 1 | grep -q 'Estado:     Pendiente'
"$BIN" show 1 | grep -q 'Resuelta:   -'
"$BIN" move 4 creada
"$BIN" ls creada --cat Sistemas | grep -q 'Actualizar VPS'
"$BIN" stats | grep -q 'En trabajo:'
"$BIN" ls all --cat Redes --priority alta | grep -q 'Total mostrado: 1'

printf '\n\nSistemas\n-\n' | "$BIN" edit 2 >/dev/null
"$BIN" show 2 | grep -q 'Categoria:  Sistemas'
"$BIN" show 2 | grep -q 'Vence:      -'

if "$BIN" rm 1 99 --yes >/dev/null 2>&1; then
  echo 'ERROR: un borrado con ID inexistente deberia fallar.' >&2
  exit 1
fi
"$BIN" ls all | grep -q 'Total mostrado: 4'
"$BIN" rm 1-2 3,4 --yes
"$BIN" ls all | grep -q 'Total mostrado: 0'
"$BIN" add 'Nueva tarea' baja Personal
"$BIN" show 5 | grep -q 'Nueva tarea'

if "$BIN" add 'Fecha invalida' alta Redes --due 2026-02-30 >/dev/null 2>&1; then
  echo 'ERROR: fecha invalida aceptada.' >&2
  exit 1
fi
"$BIN" ls all | grep -q 'Total mostrado: 1'
echo 'OK: pruebas Kanban superadas.'
