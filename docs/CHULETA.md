# Chuleta rápida — TODO Kanban

Todos los ejemplos se ejecutan con `todo` instalado en el `PATH`; si estás en `src/`, sustituye `todo` por `./todo`.

## Crear

```bash
todo add                                   # Preguntas interactivas
todo add 'Revisar BGP'                    # Prioridad media, categoría General
todo add 'Revisar BGP' alta Redes          # Alta, categoría Redes
todo add 'Preparar backups' media Sistemas --due 2026-12-01
```

Todas las tareas nuevas empiezan en estado **CREADA**. `--due` es opcional y sigue formato AAAA-MM-DD. Para indicar categoría en modo directo, introduce antes la prioridad.

## Listar y mostrar tablero

```bash
todo                       # Lo mismo que todo ls
todo ls                    # Todas las no completadas
todo ls creada             # Solo nuevas
todo ls pendiente          # Solo planificadas
todo ls trabajo            # Solo en ejecución
todo ls ok                 # Solo completadas
todo ls all                # Todas
todo ls --cat Redes
todo ls trabajo --cat Redes
todo ls --priority alta
todo ls all --cat Redes --priority alta
todo board                 # Cuatro columnas Kanban
todo board --cat Sistemas  # Tablero filtrado
todo show 3                # Detalle de tarea #3
todo cats                  # Categorías y cantidades
todo stats                 # Recuento por estado y límite WIP
```

## Mover entre estados

```bash
todo 3 plan              # CREADA -> PENDIENTE
todo 3 start             # PENDIENTE -> EN TRABAJO
todo 3 ok                # EN TRABAJO -> COMPLETADA
todo 3 reopen            # COMPLETADA -> PENDIENTE

todo move 3 creada       # Cualquier estado -> CREADA
todo move 3 pendiente    # Cualquier estado -> PENDIENTE
todo move 3 trabajo      # Cualquier estado -> EN TRABAJO
todo move 3 ok           # Cualquier estado -> COMPLETADA
```

`move` permite adelantar o retroceder fases. No permite repetir el mismo estado. El paso a EN TRABAJO falla si se alcanza el límite WIP configurado (3 por defecto). `reopen` únicamente funciona desde COMPLETADA y borra la fecha de resolución; conserva la fecha del primer inicio.

## Configurar el límite WIP

```bash
todo wip                    # Límite actual, ocupación y plazas disponibles
todo wip set 5              # Permitir hasta 5 tareas en trabajo
todo wip reset              # Restaurar el límite inicial de 3
```

Se admiten valores de 1 a 1000. El límite se conserva en `config.dat` (texto `WIP=N`), separado de las tareas binarias. Si se reduce por debajo de la ocupación actual, se conservan las tareas en trabajo pero no se admiten nuevas hasta liberar capacidad.

## Importar y exportar CSV (Feature 02)

```bash
todo export tareas.csv      # Exportar todas las tareas, incluidos estados y fechas
todo import tareas.csv      # Añadir tareas al almacén actual
```

Formato UTF-8 con separador `;`, cabecera obligatoria y nueve columnas: `id`, `descripcion`, `categoria`, `fecha_creacion`, `fecha_inicio`, `fecha_finalizacion`, `fecha_vencimiento`, `prioridad`, `estado`.

- El CSV es solo un formato de intercambio; **`tasks.dat` continúa siendo el almacén principal**.
- Al importar se asignan nuevos IDs; los IDs originales no se conservan necesariamente.
- La importación añade tareas, no reemplaza ni sincroniza las existentes. Importar dos veces puede generar duplicados.
- La validación es por lote: si un registro es inválido o se supera el WIP, no se incorpora ninguno.
- Las descripciones y categorías no admiten saltos de línea ni NUL. Se admiten comillas y `;` con el entrecomillado CSV correspondiente.
- La exportación no sobrescribe archivos existentes y **no incluye** la configuración `config.dat`.

Prueba aislada, sin modificar las tareas habituales:

```bash
mkdir -p /tmp/todo-import-lab
XDG_DATA_HOME=/tmp/todo-import-lab todo path
XDG_DATA_HOME=/tmp/todo-import-lab todo import tareas.csv
XDG_DATA_HOME=/tmp/todo-import-lab todo ls all
```

## Editar y borrar

```bash
todo edit 3                  # Modo interactivo: Enter mantiene el valor
todo rm 4                    # Pide confirmación
todo rm 2 4-7 10             # Varios ID y rango
todo rm 2,4,6 --yes          # Varios ID separados por coma; sin confirmación
```

Durante la edición, escribir `-` para categoría restaura `General`; para vencimiento elimina la fecha. El borrado rechaza todo el lote si falta cualquiera de los ID indicados.

## Utilidades

```bash
todo help                     # Ayuda
todo path                     # Ruta real de tasks.dat
NO_COLOR=1 todo board         # Desactivar secuencias de color
XDG_DATA_HOME=/tmp/todo-lab todo ls  # Usar almacén de pruebas
```

## Sesión de ejemplo

```bash
todo add 'Practicar registros' media Pascal
todo add 'Configurar laboratorio OSPF' alta Redes
todo ls creada
todo 2 plan
todo 2 start
todo board
todo show 2
todo 2 ok
todo ls ok
todo 2 reopen
todo board --cat Redes
todo stats
todo wip
```

## Campos

`ID`, `Description` (hasta 2047 bytes UTF-8), `Category` (63 bytes), `CreatedAt`, `StartedAt` (primer inicio), `CompletedAt` (última finalización válida), `DueAt` (vencimiento opcional), `Priority` (baja/media/alta) y `Status` (creada/pendiente/trabajo/completada).

## Formato y datos de prueba

Las tareas utilizan **formato binario 2**. El WIP configurable reside en `config.dat`, sin alterar dicho formato. Los datos antiguos no se leen automáticamente. Para crear un almacén totalmente independiente:

```bash
mkdir -p /tmp/todo-pruebas
XDG_DATA_HOME=/tmp/todo-pruebas todo add 'Tarea de prueba' media Test
XDG_DATA_HOME=/tmp/todo-pruebas todo board
```

No ejecutes comandos de borrado sobre tu carpeta de trabajo sin comprobar antes la ruta con `todo path`.
