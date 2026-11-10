unit uTodoStore;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  SysUtils, uTodoTypes;

function DefaultFileName: string;

type
  { Clase responsable de los datos y su persistencia; sin codigo de interfaz. }
  TTodoStore = class
  private
    FItems: TTaskArray;
    FFileName: string;
    FNextID: LongInt;
    function IndexOf(AID: LongInt): Integer;
    procedure IncludeLoadedTask(const ATask: TTaskRecord);
    procedure Save;
  public
    constructor Create(const AFileName: string = '');
    procedure Load;
    function Count: Integer;
    function Item(AIndex: Integer): TTaskRecord;
    function Find(AID: LongInt): TTaskRecord;
    function Exists(AID: LongInt): Boolean;
    function Add(const ADescription: string; APriority: TPriority;
      const ACategory: string = DEFAULT_CATEGORY; ADueAt: TDateTime = 0): LongInt;
    procedure Edit(AID: LongInt; const ADescription: string;
      APriority: TPriority; const ACategory: string; ADueAt: TDateTime);
    procedure ChangeStatus(AID: LongInt; ANewStatus: TTaskStatus);
    procedure Complete(AID: LongInt);
    procedure Reopen(AID: LongInt);
    function CountByStatus(AStatus: TTaskStatus): Integer;
    function RemoveMany(const AIDs: TIdArray): Integer;
    property FileName: string read FFileName;
  end;

implementation

uses
  BaseUnix;

function DefaultFileName: string;
var
  Base: string;
begin
  Base := GetEnvironmentVariable('XDG_DATA_HOME');
  if Base = '' then
  begin
    Base := GetEnvironmentVariable('HOME');
    if Base = '' then
      raise Exception.Create('No se encontro HOME ni XDG_DATA_HOME.');
    Base := IncludeTrailingPathDelimiter(Base) + '.local/share';
  end;
  Result := IncludeTrailingPathDelimiter(Base) + 'todo/tasks.dat';
end;

constructor TTodoStore.Create(const AFileName: string);
begin
  inherited Create;
  if AFileName <> '' then
    FFileName := AFileName
  else
    FFileName := DefaultFileName;
  FNextID := 1;
  SetLength(FItems, 0);
  if SizeOf(TTaskDiskRecord) <> 2150 then
    raise Exception.Create('Formato binario incompatible: tamano de registro inesperado.');
  Load;
end;

function TTodoStore.IndexOf(AID: LongInt): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FItems) do
    if FItems[I].ID = AID then
      Exit(I);
  Result := -1;
end;

function TTodoStore.Exists(AID: LongInt): Boolean;
begin
  Result := IndexOf(AID) >= 0;
end;

function TTodoStore.Count: Integer;
begin
  Result := Length(FItems);
end;

function TTodoStore.Item(AIndex: Integer): TTaskRecord;
begin
  if (AIndex < 0) or (AIndex >= Count) then
    raise Exception.Create('Indice de tarea fuera de rango.');
  Result := FItems[AIndex];
end;

function TTodoStore.Find(AID: LongInt): TTaskRecord;
var
  I: Integer;
begin
  I := IndexOf(AID);
  if I < 0 then
    raise Exception.CreateFmt('No existe la tarea #%d.', [AID]);
  Result := FItems[I];
end;

procedure TTodoStore.IncludeLoadedTask(const ATask: TTaskRecord);
begin
  if Exists(ATask.ID) then
    raise Exception.CreateFmt('Archivo corrupto: ID duplicado (%d).', [ATask.ID]);
  SetLength(FItems, Count + 1);
  FItems[High(FItems)] := ATask;
  if ATask.ID >= FNextID then
  begin
    if ATask.ID = High(LongInt) then
      raise Exception.Create('Se agoto el rango de identificadores.');
    FNextID := ATask.ID + 1;
  end;
end;

function ReadNextIDFromHeader(const D: TTaskDiskRecord): LongInt;
var
  I: Integer;
begin
  { La cabecera es el primer registro: ID = -proximo_ID,
    Description comienza con FILE_MAGIC y Priority = version. }
  if (D.ID >= 0) or (D.ID = Low(LongInt)) or
     (D.Priority <> FILE_FORMAT_VERSION) then
    raise Exception.Create('Cabecera no valida o version de archivo incompatible.');
  for I := 1 to Length(FILE_MAGIC) do
    if D.Description[I - 1] <> FILE_MAGIC[I] then
      raise Exception.Create('La firma del archivo de tareas no coincide.');
  Result := -D.ID;
end;

procedure TTodoStore.Load;
var
  F: TTaskFile;
  D: TTaskDiskRecord;
  Task: TTaskRecord;
  HeaderNextID: LongInt;
begin
  SetLength(FItems, 0);
  FNextID := 1;
  if not FileExists(FFileName) then
    Exit;

  AssignFile(F, FFileName);
  Reset(F);
  try
    if FileSize(F) < 1 then
      raise Exception.Create('Archivo de tareas vacio o corrupto.');
    Read(F, D);
    HeaderNextID := ReadNextIDFromHeader(D);
    while not EOF(F) do
    begin
      Read(F, D);
      DecodeTask(D, Task);
      IncludeLoadedTask(Task);
    end;
    if HeaderNextID < FNextID then
      raise Exception.Create('Archivo corrupto: proximo ID no coherente.');
    FNextID := HeaderNextID;
  finally
    CloseFile(F);
  end;
end;

procedure TTodoStore.Save;
var
  F: TTaskFile;
  D: TTaskDiskRecord;
  TempName, Dir: string;
  I: Integer;
begin
  Dir := ExtractFileDir(FFileName);
  if (not DirectoryExists(Dir)) and (not ForceDirectories(Dir)) then
    raise Exception.CreateFmt('No se pudo crear el directorio %s.', [Dir]);

  TempName := FFileName + '.tmp';
  try
    AssignFile(F, TempName);
    Rewrite(F);
    try
      FillChar(D, SizeOf(D), 0);
      D.ID := -FNextID;
      D.Priority := FILE_FORMAT_VERSION;
      for I := 1 to Length(FILE_MAGIC) do
        D.Description[I - 1] := FILE_MAGIC[I];
      Write(F, D); { Registro 0: cabecera }

      for I := 0 to High(FItems) do
      begin
        EncodeTask(FItems[I], D);
        Write(F, D);
      end;
    finally
      CloseFile(F);
    end;

    { Al estar en el mismo directorio, rename sustituye el archivo en un paso. }
    if fpRename(PChar(TempName), PChar(FFileName)) <> 0 then
      raise Exception.CreateFmt('No se pudo actualizar %s.', [FFileName]);
  except
    DeleteFile(TempName);
    raise;
  end;
end;

function TTodoStore.Add(const ADescription: string; APriority: TPriority;
  const ACategory: string; ADueAt: TDateTime): LongInt;
var
  Task: TTaskRecord;
  CheckDisk: TTaskDiskRecord;
begin
  if FNextID >= High(LongInt) then
    raise Exception.Create('Se agoto el rango de identificadores.');
  Task.ID := FNextID;
  Task.Description := Trim(ADescription);
  Task.Category := Trim(ACategory);
  if Task.Category = '' then
    Task.Category := DEFAULT_CATEGORY;
  Task.CreatedAt := Now;
  Task.StartedAt := 0;
  Task.CompletedAt := 0;
  Task.DueAt := ADueAt;
  Task.Priority := APriority;
  Task.Status := tsCreada;
  EncodeTask(Task, CheckDisk); { Validar ANTES de tocar el array }
  SetLength(FItems, Count + 1);
  FItems[High(FItems)] := Task;
  Inc(FNextID);
  Save;
  Result := Task.ID;
end;

procedure TTodoStore.Edit(AID: LongInt; const ADescription: string;
  APriority: TPriority; const ACategory: string; ADueAt: TDateTime);
var
  I: Integer;
  Task: TTaskRecord;
  CheckDisk: TTaskDiskRecord;
begin
  I := IndexOf(AID);
  if I < 0 then
    raise Exception.CreateFmt('No existe la tarea #%d.', [AID]);
  Task := FItems[I];
  Task.Description := Trim(ADescription);
  Task.Category := Trim(ACategory);
  if Task.Category = '' then
    Task.Category := DEFAULT_CATEGORY;
  Task.Priority := APriority;
  Task.DueAt := ADueAt;
  EncodeTask(Task, CheckDisk);
  FItems[I] := Task;
  Save;
end;

function TTodoStore.CountByStatus(AStatus: TTaskStatus): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FItems) do
    if FItems[I].Status = AStatus then Inc(Result);
end;

procedure TTodoStore.ChangeStatus(AID: LongInt; ANewStatus: TTaskStatus);
var
  I: Integer;
  OldStatus: TTaskStatus;
begin
  I := IndexOf(AID);
  if I < 0 then
    raise Exception.CreateFmt('No existe la tarea #%d.', [AID]);
  OldStatus := FItems[I].Status;
  if OldStatus = ANewStatus then
    raise Exception.CreateFmt('La tarea #%d ya esta en estado %s.',
      [AID, StatusText(ANewStatus)]);

  if (ANewStatus = tsEnTrabajo) and (CountByStatus(tsEnTrabajo) >= MAX_WIP) then
    raise Exception.CreateFmt('Limite WIP alcanzado (%d). Finaliza o mueve otra tarea.',
      [MAX_WIP]);

  if (OldStatus = tsCompletada) and (ANewStatus <> tsCompletada) then
    FItems[I].CompletedAt := 0;

  if (ANewStatus = tsEnTrabajo) and (FItems[I].StartedAt = 0) then
    FItems[I].StartedAt := Now;

  if ANewStatus = tsCompletada then
    FItems[I].CompletedAt := Now;

  FItems[I].Status := ANewStatus;
  Save;
end;

procedure TTodoStore.Complete(AID: LongInt);
begin
  ChangeStatus(AID, tsCompletada);
end;

procedure TTodoStore.Reopen(AID: LongInt);
var
  Task: TTaskRecord;
begin
  Task := Find(AID);
  if Task.Status <> tsCompletada then
    raise Exception.CreateFmt('La tarea #%d no esta completada.', [AID]);
  ChangeStatus(AID, tsPendiente);
end;

function TTodoStore.RemoveMany(const AIDs: TIdArray): Integer;
var
  I, J, K: Integer;
  Selected: Boolean;
begin
  { Si falta un ID, no se borra ninguno. }
  for K := 0 to High(AIDs) do
    if not Exists(AIDs[K]) then
      raise Exception.CreateFmt('No existe la tarea #%d. No se elimino ninguna.', [AIDs[K]]);

  Result := 0;
  for I := High(FItems) downto 0 do
  begin
    Selected := False;
    for K := 0 to High(AIDs) do
      if FItems[I].ID = AIDs[K] then
      begin
        Selected := True;
        Break;
      end;
    if Selected then
    begin
      for J := I to High(FItems) - 1 do
        FItems[J] := FItems[J + 1];
      SetLength(FItems, Count - 1);
      Inc(Result);
    end;
  end;
  if Result > 0 then
    Save;
end;

end.
