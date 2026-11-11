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

`move` permite adelantar o retroceder fases. No permite repetir el mismo estado. El paso a EN TRABAJO falla si se alcanza el límite WIP configurado (por defecto, 3). `reopen` únicamente funciona desde COMPLETADA y borra la fecha de resolución; conserva la fecha del primer inicio.

## Configurar el límite WIP

```bash
todo wip                    # Consultar límite, ocupación y plazas disponibles
todo wip set 5              # Fijar máximo de cinco tareas EN TRABAJO
todo wip reset              # Volver al límite predeterminado de 3
```

El rango permitido es de **1 a 1000**. El límite se conserva entre ejecuciones en `config.dat`, junto a `tasks.dat`. `board` y `stats` muestran la ocupación respecto al límite actual. Si reduces el WIP por debajo de las tareas que ya están en curso, estas permanecen en su estado; no se admiten nuevas entradas a EN TRABAJO hasta liberar capacidad.

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

Las tareas utilizan **formato binario 2** (`tasks.dat`). La configuración WIP se guarda aparte como texto `WIP=N` (`config.dat`); no cambia el formato de las tareas. Los datos binarios antiguos no se leen automáticamente. Para crear un almacén totalmente independiente:

```bash
mkdir -p /tmp/todo-pruebas
XDG_DATA_HOME=/tmp/todo-pruebas todo add 'Tarea de prueba' media Test
XDG_DATA_HOME=/tmp/todo-pruebas todo wip set 2
XDG_DATA_HOME=/tmp/todo-pruebas todo board
```

No ejecutes comandos de borrado sobre tu carpeta de trabajo sin comprobar antes la ruta con `todo path`.
