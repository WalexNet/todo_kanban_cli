program todo;

{$mode objfpc}{$H+}
{$codepage utf8}

uses
  {$IFDEF UNIX}
  cwstring,
  {$ENDIF}
  SysUtils, uTodoTypes, uTodoStore, uTodoConsole;

const
  MAX_REMOVE_IDS = 1000;

function RequireID(AIndex: Integer): LongInt;
begin
  if (ParamCount < AIndex) or (not TryStrToInt(ParamStr(AIndex), Result)) or
     (Result <= 0) then
    raise Exception.CreateFmt('Se esperaba un ID entero positivo en argumento %d.',
      [AIndex]);
end;

procedure RequireParams(ACount: Integer);
begin
  if ParamCount <> ACount then
    raise Exception.Create('Numero de argumentos incorrecto. Consulta: todo help');
end;

function AskDueDate(const AText: string): TDateTime;
begin
  if AText = '' then
    Exit(0);
  if not TryISODate(AText, Result) then
    raise Exception.Create('Fecha invalida. Formato esperado: AAAA-MM-DD.');
end;

procedure RunAdd(AStore: TTodoStore);
var
  Description, PriorityInput, DueInput, CategoryInput, Arg: string;
  Priority: TPriority;
  DueDate: TDateTime;
  NewID: LongInt;
  I, Positionals: Integer;
  DueSpecified: Boolean;
begin
  if ParamCount = 1 then
  begin
    Writeln('Nueva tarea');
    Description := Prompt('Descripcion: ');
    PriorityInput := Prompt('Prioridad [baja/media/alta] (media): ');
    CategoryInput := Prompt('Categoria (General): ');
    if CategoryInput = '' then
      CategoryInput := DEFAULT_CATEGORY;
    DueInput := Prompt('Vencimiento [AAAA-MM-DD] (opcional): ');
    Priority := ParsePriority(PriorityInput);
    DueDate := AskDueDate(DueInput);
  end
  else
  begin
    Description := ParamStr(2);
    Priority := prMedia;
    CategoryInput := DEFAULT_CATEGORY;
    DueDate := 0;
    DueSpecified := False;
    Positionals := 0;
    I := 3;
    while I <= ParamCount do
    begin
      Arg := ParamStr(I);
      if Arg = '--due' then
      begin
        if DueSpecified or (I + 1 > ParamCount) then
          raise Exception.Create('Uso: --due AAAA-MM-DD (una sola vez).');
        Inc(I);
        DueDate := AskDueDate(ParamStr(I));
        if DueDate = 0 then
          raise Exception.Create('El vencimiento requiere una fecha AAAA-MM-DD.');
        DueSpecified := True;
      end
      else
      begin
        if (Length(Arg) >= 2) and (Copy(Arg, 1, 2) = '--') then
          raise Exception.CreateFmt('Opcion desconocida: %s.', [Arg]);
        Inc(Positionals);
        case Positionals of
          1: Priority := ParsePriority(Arg);
          2: CategoryInput := Arg;
        else
          raise Exception.Create('Uso: todo add "Descripcion" [prioridad] ["Categoria"] [--due FECHA]');
        end;
      end;
      Inc(I);
    end;
  end;
  NewID := AStore.Add(Description, Priority, CategoryInput, DueDate);
  PrintSuccess(Format('Tarea #%d creada.', [NewID]));
end;

procedure RunEdit(AStore: TTodoStore);
var
  Task: TTaskRecord;
  Description, InputPriority, InputDue, InputCategory, Category: string;
  Priority: TPriority;
  DueDate: TDateTime;
  ID: LongInt;
begin
  RequireParams(2);
  ID := RequireID(2);
  Task := AStore.Find(ID);
  PrintDetail(Task);
  Writeln;
  Writeln('Introduce los nuevos valores. Enter conserva el anterior.');
  Description := Prompt('Descripcion: ');
  if Description = '' then
    Description := Task.Description;
  InputPriority := Prompt('Prioridad [baja/media/alta]: ');
  if InputPriority = '' then
    Priority := Task.Priority
  else
    Priority := ParsePriority(InputPriority);
  InputCategory := Prompt('Categoria (Enter conserva, "-" = General): ');
  if InputCategory = '' then
    Category := Task.Category
  else if InputCategory = '-' then
    Category := DEFAULT_CATEGORY
  else
    Category := InputCategory;
  InputDue := Prompt('Vencimiento [AAAA-MM-DD] ("-" para borrar): ');
  if InputDue = '' then
    DueDate := Task.DueAt
  else if InputDue = '-' then
    DueDate := 0
  else
    DueDate := AskDueDate(InputDue);
  AStore.Edit(ID, Description, Priority, Category, DueDate);
  PrintSuccess(Format('Tarea #%d actualizada.', [ID]));
end;

procedure AddUniqueID(var AIDs: TIdArray; AID: LongInt);
var
  I: Integer;
begin
  for I := 0 to High(AIDs) do
    if AIDs[I] = AID then
      Exit;
  if Length(AIDs) >= MAX_REMOVE_IDS then
    raise Exception.CreateFmt('Limite de %d IDs por operacion.', [MAX_REMOVE_IDS]);
  SetLength(AIDs, Length(AIDs) + 1);
  AIDs[High(AIDs)] := AID;
end;

procedure ParsePiece(const APiece: string; var AIDs: TIdArray);
var
  Dash, FirstID, LastID, N: LongInt;
begin
  if APiece = '' then
    raise Exception.Create('Lista de IDs vacia.');
  Dash := Pos('-', APiece);
  if Dash = 0 then
  begin
    if not TryStrToInt(APiece, FirstID) or (FirstID <= 0) then
      raise Exception.CreateFmt('ID invalido: %s.', [APiece]);
    AddUniqueID(AIDs, FirstID);
    Exit;
  end;
  if not TryStrToInt(Copy(APiece, 1, Dash - 1), FirstID) or
     not TryStrToInt(Copy(APiece, Dash + 1, Length(APiece)), LastID) or
     (FirstID <= 0) or (LastID < FirstID) then
    raise Exception.CreateFmt('Rango invalido: %s.', [APiece]);
  if LastID - FirstID >= MAX_REMOVE_IDS then
    raise Exception.Create('Rango demasiado grande.');
  for N := FirstID to LastID do
    AddUniqueID(AIDs, N);
end;

procedure ParseIDSpec(const ASpec: string; var AIDs: TIdArray);
var
  Remaining, Piece: string;
  Comma: Integer;
begin
  Remaining := ASpec;
  repeat
    Comma := Pos(',', Remaining);
    if Comma = 0 then
    begin
      ParsePiece(Trim(Remaining), AIDs);
      Break;
    end;
    Piece := Copy(Remaining, 1, Comma - 1);
    ParsePiece(Trim(Piece), AIDs);
    Delete(Remaining, 1, Comma);
  until False;
end;

procedure RunRemove(AStore: TTodoStore);
var
  I, Removed: Integer;
  IDs: TIdArray;
  SkipConfirm: Boolean;
begin
  if ParamCount < 2 then
    raise Exception.Create('Uso: todo rm ID [ID|PRIMERO-ULTIMO]... [--yes]');
  SetLength(IDs, 0);
  SkipConfirm := False;
  for I := 2 to ParamCount do
  begin
    if ParamStr(I) = '--yes' then
      SkipConfirm := True
    else
      ParseIDSpec(ParamStr(I), IDs);
  end;
  if Length(IDs) = 0 then
    raise Exception.Create('No se indicaron tareas para borrar.');

  { Comprobar todos los IDs antes de borrar uno solo. }
  for I := 0 to High(IDs) do
    if not AStore.Exists(IDs[I]) then
      raise Exception.CreateFmt('No existe la tarea #%d. No se elimino ninguna.', [IDs[I]]);

  if (not SkipConfirm) and
     (not Confirm(Format('Eliminar definitivamente %d tarea(s)?', [Length(IDs)]))) then
  begin
    Writeln('Cancelado; no se ha eliminado nada.');
    Exit;
  end;
  Removed := AStore.RemoveMany(IDs);
  PrintSuccess(Format('%d tarea(s) eliminada(s).', [Removed]));
end;

procedure RunCommand(AStore: TTodoStore);
var
  Cmd, Filter, Action, CatFilter, PriorityFilter: string;
  ID: LongInt;
  ArgIdx: Integer;
begin
  if ParamCount = 0 then
    Cmd := 'ls'
  else
    Cmd := LowerCase(ParamStr(1));

  if (Cmd = 'help') or (Cmd = '-h') or (Cmd = '--help') then
  begin
    PrintHelp;
    Exit;
  end;

  if Cmd = 'ls' then
  begin
    Filter := 'pendientes'; { Por defecto: todas las no completadas }
    CatFilter := '';
    PriorityFilter := '';
    ArgIdx := 2;
    if (ArgIdx <= ParamCount) and
       ((LowerCase(ParamStr(ArgIdx)) = 'ok') or
        (LowerCase(ParamStr(ArgIdx)) = 'all') or
        (LowerCase(ParamStr(ArgIdx)) = 'creada') or
        (LowerCase(ParamStr(ArgIdx)) = 'pendiente') or
        (LowerCase(ParamStr(ArgIdx)) = 'trabajo')) then
    begin
      Filter := LowerCase(ParamStr(ArgIdx));
      Inc(ArgIdx);
    end;
    while ArgIdx <= ParamCount do
    begin
      if (ParamStr(ArgIdx) = '--cat') and (CatFilter = '') then
      begin
        if ArgIdx + 1 > ParamCount then
          raise Exception.Create('Falta el nombre despues de --cat.');
        CatFilter := Trim(ParamStr(ArgIdx + 1));
        if CatFilter = '' then
          raise Exception.Create('La categoria del filtro no puede estar vacia.');
      end
      else if (ParamStr(ArgIdx) = '--priority') and (PriorityFilter = '') then
      begin
        if ArgIdx + 1 > ParamCount then
          raise Exception.Create('Falta la prioridad despues de --priority.');
        PriorityFilter := PriorityText(ParsePriority(ParamStr(ArgIdx + 1)));
      end
      else
        raise Exception.Create('Uso: todo ls [creada|pendiente|trabajo|ok|all] [--cat CATEGORIA] [--priority baja|media|alta]');
      Inc(ArgIdx, 2);
    end;
    PrintList(AStore, Filter, CatFilter, PriorityFilter);
  end
  else if Cmd = 'board' then
  begin
    CatFilter := '';
    if ParamCount = 3 then
    begin
      if (ParamStr(2) <> '--cat') or (Trim(ParamStr(3)) = '') then
        raise Exception.Create('Uso: todo board [--cat CATEGORIA]');
      CatFilter := Trim(ParamStr(3));
    end
    else if ParamCount <> 1 then
      raise Exception.Create('Uso: todo board [--cat CATEGORIA]');
    PrintBoard(AStore, CatFilter);
  end
  else if Cmd = 'move' then
  begin
    RequireParams(3);
    ID := RequireID(2);
    Action := ParamStr(3);
    AStore.ChangeStatus(ID, ParseStatus(Action));
    PrintSuccess(Format('Tarea #%d movida a %s.',
      [ID, StatusText(AStore.Find(ID).Status)]));
  end
  else if Cmd = 'add' then
    RunAdd(AStore)
  else if Cmd = 'edit' then
    RunEdit(AStore)
  else if Cmd = 'rm' then
    RunRemove(AStore)
  else if Cmd = 'show' then
  begin
    RequireParams(2);
    PrintDetail(AStore.Find(RequireID(2)));
  end
  else if Cmd = 'cats' then
  begin
    RequireParams(1);
    PrintCategories(AStore);
  end
  else if Cmd = 'stats' then
  begin
    RequireParams(1);
    PrintStats(AStore);
  end
  else if Cmd = 'path' then
  begin
    RequireParams(1);
    Writeln(AStore.FileName);
  end
  else if TryStrToInt(Cmd, ID) and (ID > 0) then
  begin
    RequireParams(2);
    Action := LowerCase(ParamStr(2));
    if Action = 'ok' then
    begin
      AStore.Complete(ID);
      PrintSuccess(Format('Tarea #%d completada.', [ID]));
    end
    else if Action = 'reopen' then
    begin
      AStore.Reopen(ID);
      PrintSuccess(Format('Tarea #%d reabierta como PENDIENTE.', [ID]));
    end
    else if Action = 'plan' then
    begin
      AStore.ChangeStatus(ID, tsPendiente);
      PrintSuccess(Format('Tarea #%d ahora PENDIENTE.', [ID]));
    end
    else if Action = 'start' then
    begin
      AStore.ChangeStatus(ID, tsEnTrabajo);
      PrintSuccess(Format('Tarea #%d ahora EN TRABAJO.', [ID]));
    end
    else
      raise Exception.Create('Uso: todo N plan | start | ok | reopen');
  end
  else
    raise Exception.CreateFmt('Comando desconocido: %s. Consulta: todo help', [Cmd]);
end;

var
  Store: TTodoStore;
begin
  if (ParamCount > 0) and ((LowerCase(ParamStr(1)) = 'help') or
     (ParamStr(1) = '-h') or (ParamStr(1) = '--help')) then
  begin
    PrintHelp;
    Halt(0);
  end;
  { path no requiere abrir la base de datos; util incluso si hay formato anterior. }
  if (ParamCount > 0) and (LowerCase(ParamStr(1)) = 'path') then
  begin
    if ParamCount <> 1 then
    begin
      PrintError('Uso: todo path');
      Halt(1);
    end;
    try
      Writeln(DefaultFileName);
    except
      on E: Exception do
      begin
        PrintError(E.Message);
        Halt(1);
      end;
    end;
    Halt(0);
  end;

  Store := nil;
  try
    Store := TTodoStore.Create;
    RunCommand(Store);
  except
    on E: Exception do
    begin
      PrintError(E.Message);
      Halt(1);
    end;
  end;
  Store.Free;
end.
