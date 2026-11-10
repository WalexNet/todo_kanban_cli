unit uTodoConsole;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  SysUtils, uTodoTypes, uTodoStore;

procedure PrintHelp;
procedure PrintList(AStore: TTodoStore; const AFilter: string;
  const ACategory: string = ''; const APriority: string = '');
procedure PrintDetail(const ATask: TTaskRecord);
procedure PrintBoard(AStore: TTodoStore; const ACategory: string = '');
procedure PrintCategories(AStore: TTodoStore);
procedure PrintStats(AStore: TTodoStore);
procedure PrintSuccess(const AMessage: string);
procedure PrintError(const AMessage: string);
function Prompt(const AMessage: string): string;
function Confirm(const AMessage: string): Boolean;

implementation

const
  ESC = #27'[';
  RESET = ESC + '0m';
  BOLD = ESC + '1m';
  CYAN = ESC + '36m';
  GREEN = ESC + '32m';
  YELLOW = ESC + '33m';
  RED = ESC + '31m';
  BLUE = ESC + '34m';
  MAGENTA = ESC + '35m';
  DIM = ESC + '2m';

function ColorsEnabled: Boolean;
begin
  Result := (GetEnvironmentVariable('NO_COLOR') = '') and
            (GetEnvironmentVariable('TERM') <> 'dumb');
end;

function Paint(const S, Color: string): string;
begin
  if ColorsEnabled then
    Result := Color + S + RESET
  else
    Result := S;
end;

function PriorityColor(APriority: TPriority): string;
begin
  case APriority of
    prBaja: Result := GREEN;
    prMedia: Result := YELLOW;
    prAlta: Result := RED;
  end;
end;

function StatusColor(AStatus: TTaskStatus): string;
begin
  case AStatus of
    tsCreada: Result := CYAN;
    tsPendiente: Result := YELLOW;
    tsEnTrabajo: Result := BLUE;
    tsCompletada: Result := GREEN;
  else
    Result := RESET;
  end;
end;

function DateTimeText(ADate: TDateTime): string;
begin
  if ADate = 0 then
    Result := '-'
  else
    Result := FormatDateTime('yyyy-mm-dd hh:nn', ADate);
end;

procedure PrintWrapped(const S: string; Indent: string = '    ');
var
  P, L, WordStart: Integer;
  WordText, LineText: string;
begin
  P := 1;
  L := Length(S);
  LineText := '';
  while P <= L do
  begin
    while (P <= L) and (S[P] = ' ') do
      Inc(P);
    if P > L then
      Break;
    WordStart := P;
    while (P <= L) and (S[P] <> ' ') do
      Inc(P);
    WordText := Copy(S, WordStart, P - WordStart);
    if (LineText <> '') and (Length(LineText) + 1 + Length(WordText) > 72) then
    begin
      Writeln(Indent, LineText);
      LineText := WordText;
    end
    else if LineText = '' then
      LineText := WordText
    else
      LineText := LineText + ' ' + WordText;
  end;
  if LineText <> '' then
    Writeln(Indent, LineText);
end;

procedure PrintHelp;
begin
  Writeln(Paint('TODO · Gestor Kanban de tareas en Free Pascal', BOLD + CYAN));
  Writeln;
  Writeln('Uso: todo COMANDO [ARGUMENTOS]');
  Writeln;
  Writeln('  todo board                      Tablero Kanban (4 estados)');
  Writeln('  todo board --cat Redes          Tablero de una categoria');
  Writeln('  todo ls                         Tareas sin completar');
  Writeln('  todo ls creada                  Tareas recien creadas');
  Writeln('  todo ls pendiente               Tareas planificadas');
  Writeln('  todo ls trabajo                 Tareas en ejecucion');
  Writeln('  todo ls ok                      Completadas');
  Writeln('  todo ls all                     Todas');
  Writeln('  todo ls --cat Redes --priority alta');
  Writeln('  todo ls trabajo --cat Redes');
  Writeln('  todo cats                       Categorias y recuentos');
  Writeln('  todo add                        Nueva tarea interactiva (CREADA)');
  Writeln('  todo add "Texto" alta "Redes"   Nueva tarea directa');
  Writeln('  todo add "Texto" alta Redes --due 2026-12-01');
  Writeln('  todo edit 3                     Editar datos de la tarea');
  Writeln('  todo 6 plan                     Pasar a PENDIENTE');
  Writeln('  todo 6 start                    Pasar a EN TRABAJO');
  Writeln('  todo 6 ok                       Pasar a COMPLETADA');
  Writeln('  todo 6 reopen                   Reabrir como PENDIENTE');
  Writeln('  todo move 6 creada|pendiente|trabajo|ok');
  Writeln('  todo rm 2 4-7 9,11             Eliminar IDs y rangos');
  Writeln('  todo rm 2 4-7 --yes             Eliminar sin confirmacion');
  Writeln('  todo show 3                     Ver detalle');
  Writeln('  todo stats                      Estadisticas y limite WIP');
  Writeln('  todo path                       Ruta del archivo binario');
  Writeln('  todo help                       Esta ayuda');
  Writeln;
  Writeln('Estado inicial: CREADA. Limite EN TRABAJO: ', MAX_WIP, '.');
  Writeln('Prioridades: baja, media (por defecto), alta.');
  Writeln('Categoria: texto libre, General por defecto (max. 63 bytes UTF-8).');
  Writeln('Fecha: AAAA-MM-DD. En edicion, "-" elimina el vencimiento.');
  Writeln('add directo: para indicar categoria, indica tambien prioridad.');
  Writeln('Colores: NO_COLOR=1 para desactivarlos.');
end;

procedure PrintList(AStore: TTodoStore; const AFilter: string;
  const ACategory: string; const APriority: string);
var
  I, Shown: Integer;
  Task: TTaskRecord;
  DisplayIt: Boolean;
  Heading: string;
begin
  Heading := 'TAREAS · ' + UpperCase(AFilter);
  if ACategory <> '' then
    Heading := Heading + ' · ' + ACategory;
  if APriority <> '' then
    Heading := Heading + ' · Prioridad ' + APriority;
  Writeln(Paint(Heading, BOLD + CYAN));
  Writeln(Paint(StringOfChar('-', 76), DIM));
  Shown := 0;
  for I := 0 to AStore.Count - 1 do
  begin
    Task := AStore.Item(I);
    DisplayIt := (AFilter = 'all') or
      ((AFilter = 'pendientes') and (Task.Status <> tsCompletada)) or
      ((AFilter = StatusKey(Task.Status)));
    if (ACategory <> '') and (not SameText(ACategory, Task.Category)) then
      DisplayIt := False;
    if (APriority <> '') and (not SameText(APriority, PriorityText(Task.Priority))) then
      DisplayIt := False;
    if not DisplayIt then
      Continue;
    Inc(Shown);
    Write(' ', Paint(Format('#%-5d', [Task.ID]), BOLD + CYAN));
    Write(' ', Paint(Format('%-6s', [UpperCase(PriorityText(Task.Priority))]),
      PriorityColor(Task.Priority)));
    Write(' ', Paint(Format('%-12s', [UpperCase(StatusText(Task.Status))]), StatusColor(Task.Status)));
    Writeln(' Creada: ', DateTimeText(Task.CreatedAt));
    Writeln('    Categoria: ', Paint(Task.Category, CYAN));
    PrintWrapped(Task.Description);
    if Task.DueAt <> 0 then
    begin
      if (Task.Status <> tsCompletada) and (Task.DueAt < Date) then
        Writeln('    ', Paint('Vencida: ' + ISODate(Task.DueAt), RED))
      else
        Writeln('    Vence: ', ISODate(Task.DueAt));
    end;
    Writeln;
  end;
  if Shown = 0 then
    Writeln('  Sin tareas en esta vista.');
  Writeln(Paint(Format('Total mostrado: %d', [Shown]), DIM));
end;

procedure PrintDetail(const ATask: TTaskRecord);
begin
  Writeln(Paint(Format('TAREA #%d', [ATask.ID]), BOLD + CYAN));
  Writeln(Paint(StringOfChar('-', 76), DIM));
  Writeln('Estado:     ', Paint(StatusText(ATask.Status), StatusColor(ATask.Status)));
  Writeln('Prioridad:  ', Paint(PriorityText(ATask.Priority), PriorityColor(ATask.Priority)));
  Writeln('Categoria:  ', Paint(ATask.Category, CYAN));
  Writeln('Creada:     ', DateTimeText(ATask.CreatedAt));
  Writeln('Inicio:     ', DateTimeText(ATask.StartedAt));
  Writeln('Resuelta:   ', DateTimeText(ATask.CompletedAt));
  Writeln('Vence:      ', ISODate(ATask.DueAt));
  Writeln('Descripcion:');
  PrintWrapped(ATask.Description);
end;

procedure PrintCategories(AStore: TTodoStore);
var
  Names: array of string;
  Counts: array of Integer;
  I, J, Index: Integer;
  Task: TTaskRecord;
begin
  SetLength(Names, 0);
  SetLength(Counts, 0);
  for I := 0 to AStore.Count - 1 do
  begin
    Task := AStore.Item(I);
    Index := -1;
    for J := 0 to High(Names) do
      if SameText(Names[J], Task.Category) then
      begin
        Index := J;
        Break;
      end;
    if Index < 0 then
    begin
      Index := Length(Names);
      SetLength(Names, Index + 1);
      SetLength(Counts, Index + 1);
      Names[Index] := Task.Category;
      Counts[Index] := 0;
    end;
    Inc(Counts[Index]);
  end;
  Writeln(Paint('TODO · Categorias', BOLD + CYAN));
  if Length(Names) = 0 then
    Writeln('  Sin categorias: todavia no hay tareas.');
  for I := 0 to High(Names) do
    Writeln('  ', Paint(Names[I], CYAN), '  (', Counts[I], ')');
end;

procedure PrintStats(AStore: TTodoStore);
var
  I, Created, Pending, Working, Done, HighPriority, Overdue: Integer;
  Task: TTaskRecord;
begin
  Created := 0; Pending := 0; Working := 0; Done := 0;
  HighPriority := 0; Overdue := 0;
  for I := 0 to AStore.Count - 1 do
  begin
    Task := AStore.Item(I);
    case Task.Status of
      tsCreada: Inc(Created);
      tsPendiente: Inc(Pending);
      tsEnTrabajo: Inc(Working);
      tsCompletada: Inc(Done);
    end;
    if Task.Status <> tsCompletada then
    begin
      if Task.Priority = prAlta then Inc(HighPriority);
      if (Task.DueAt > 0) and (Task.DueAt < Date) then Inc(Overdue);
    end;
  end;
  Writeln(Paint('TODO · Estadisticas Kanban', BOLD + CYAN));
  Writeln('  Total:                 ', AStore.Count);
  Writeln('  Creadas:               ', Created);
  Writeln('  Pendientes:            ', Pending);
  Writeln('  En trabajo:            ', Working, '/', MAX_WIP);
  Writeln('  Completadas:           ', Done);
  Writeln('  Sin completar:         ', Created + Pending + Working);
  Writeln('  Sin completar alta:    ', HighPriority);
  Writeln('  Vencidas abiertas:     ', Overdue);
end;

{ Contar caracteres UTF-8 (aproximacion: una columna por punto de codigo).
  No es un calculo de ancho de terminal para emojis ni caracteres combinados. }
function UTF8Chars(const S: string): Integer;
var I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
    if (Ord(S[I]) and $C0) <> $80 then Inc(Result);
end;

function ClipUTF8(const S: string; AWidth: Integer): string;
var I, Chars, CutPos: Integer;
begin
  if AWidth <= 0 then Exit('');
  if UTF8Chars(S) <= AWidth then Exit(S);
  Chars := 0;
  CutPos := 0;
  for I := 1 to Length(S) do
    if (Ord(S[I]) and $C0) <> $80 then
    begin
      Inc(Chars);
      if Chars > AWidth - 1 then Break;
      CutPos := I;
    end;
  { Copy hasta el comienzo del siguiente caracter evita partir secuencias UTF-8. }
  if (AWidth = 1) then Exit('…');
  if CutPos = 0 then Exit('…');
  I := CutPos + 1;
  while (I <= Length(S)) and ((Ord(S[I]) and $C0) = $80) do Inc(I);
  Result := Copy(S, 1, I - 1) + '…';
end;

function PadCell(const S: string; AWidth: Integer): string;
var T: string;
begin
  T := ClipUTF8(S, AWidth);
  Result := T + StringOfChar(' ', AWidth - UTF8Chars(T));
end;

procedure PrintBoard(AStore: TTodoStore; const ACategory: string);
const
  W = 28;
  PAD = ' | ';
var
  Groups: array[0..3] of TTaskArray;
  Counts: array[0..3] of Integer;
  I, J, S, MaxRows, Row, Index: Integer;
  Task: TTaskRecord;
  Head, CellText, Line: string;
  Titles: array[0..3] of string;
begin
  for S := 0 to 3 do
  begin
    Counts[S] := 0;
    SetLength(Groups[S], 0);
    Titles[S] := UpperCase(StatusText(TTaskStatus(S)));
  end;
  MaxRows := 0;
  for I := 0 to AStore.Count - 1 do
  begin
    Task := AStore.Item(I);
    if (ACategory <> '') and (not SameText(Task.Category, ACategory)) then Continue;
    S := Ord(Task.Status);
    Index := Counts[S];
    SetLength(Groups[S], Index + 1);
    Groups[S][Index] := Task;
    Inc(Counts[S]);
    if Counts[S] > MaxRows then MaxRows := Counts[S];
  end;
  Head := 'TODO · TABLERO KANBAN';
  if ACategory <> '' then Head := Head + ' · ' + ACategory;
  Writeln(Paint(Head, BOLD + CYAN));
  Writeln(Paint(Format('En trabajo: %d/%d', [Counts[2], MAX_WIP]), DIM));
  Writeln;
  { Cada tarjeta usa tres filas; salida de cuatro columnas para terminal ancha. }
  Line := '';
  for S := 0 to 3 do
  begin
    if S > 0 then Line := Line + PAD;
    Line := Line + Paint(PadCell(Format('%s (%d)', [Titles[S], Counts[S]]), W),
      BOLD + StatusColor(TTaskStatus(S)));
  end;
  Writeln(Line);
  Writeln(StringOfChar('-', 4 * W + 3 * Length(PAD)));
  for Row := 0 to MaxRows - 1 do
  begin
    for J := 0 to 2 do
    begin
      Line := '';
      for S := 0 to 3 do
      begin
        if S > 0 then Line := Line + PAD;
        CellText := '';
        if Row < Counts[S] then
        begin
          Task := Groups[S][Row];
          case J of
            0: CellText := Format('#%d  [%s]', [Task.ID, UpperCase(PriorityText(Task.Priority))]);
            1: CellText := Task.Description;
            2: CellText := '· ' + Task.Category;
          end;
        end;
        if (Row < Counts[S]) and (J = 0) then
          Line := Line + Paint(PadCell(CellText, W), PriorityColor(Task.Priority))
        else
          Line := Line + PadCell(CellText, W);
      end;
      Writeln(Line);
    end;
    Writeln(Paint(StringOfChar('-', 4 * W + 3 * Length(PAD)), DIM));
  end;
  if MaxRows = 0 then Writeln('  No hay tareas para este tablero.');
end;

procedure PrintSuccess(const AMessage: string);
begin
  Writeln(Paint('OK  ' + AMessage, GREEN));
end;

procedure PrintError(const AMessage: string);
begin
  Writeln(StdErr, Paint('ERROR  ' + AMessage, RED));
end;

function Prompt(const AMessage: string): string;
begin
  Write(Paint('> ', CYAN), AMessage);
  ReadLn(Result);
  Result := Trim(Result);
end;

function Confirm(const AMessage: string): Boolean;
var
  Answer: string;
begin
  Answer := LowerCase(Prompt(AMessage + ' [s/N]: '));
  Result := (Answer = 's') or (Answer = 'si') or (Answer = 'sí');
end;

end.
