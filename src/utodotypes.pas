unit uTodoTypes;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  SysUtils;

const
  MAX_DESCRIPTION_BYTES = 2047;
  MAX_CATEGORY_BYTES = 63;
  DESCRIPTION_CAPACITY = MAX_DESCRIPTION_BYTES + 1;
  CATEGORY_CAPACITY = MAX_CATEGORY_BYTES + 1;
  DEFAULT_CATEGORY = 'General';
  FILE_FORMAT_VERSION = 2;
  FILE_MAGIC = 'TODO-FPC-2';
  DEFAULT_WIP = 3; { Limite inicial de tareas EN TRABAJO }
  MAX_ALLOWED_WIP = 1000; { Limite superior de configuracion }

type
  TPriority = (prBaja, prMedia, prAlta);
  TTaskStatus = (tsCreada, tsPendiente, tsEnTrabajo, tsCompletada);

  { Modelo de dominio: datos faciles de manejar en RAM. }
  TTaskRecord = record
    ID: LongInt;
    Description: string;
    Category: string;
    CreatedAt: TDateTime;
    StartedAt: TDateTime;   { Primera vez que entro EN TRABAJO; 0 = nunca }
    CompletedAt: TDateTime; { 0 salvo si esta COMPLETADA }
    DueAt: TDateTime;
    Priority: TPriority;
    Status: TTaskStatus;
  end;

  { Representacion persistente: solo campos de longitud fija, sin punteros. }
  TTaskDiskRecord = packed record
    ID: LongInt;
    Description: array[0..MAX_DESCRIPTION_BYTES] of AnsiChar;
    Category: array[0..MAX_CATEGORY_BYTES] of AnsiChar;
    CreatedAt: Double;
    StartedAt: Double;
    CompletedAt: Double;
    DueAt: Double;
    Priority: Byte;
    Status: Byte;
  end;

  TTaskFile = file of TTaskDiskRecord;
  TTaskArray = array of TTaskRecord;
  TIdArray = array of LongInt;

function PriorityText(APriority: TPriority): string;
function StatusText(AStatus: TTaskStatus): string;
function StatusKey(AStatus: TTaskStatus): string;
function ParsePriority(const AText: string): TPriority;
function ParseStatus(const AText: string): TTaskStatus;
function TryISODate(const AText: string; out ADate: TDateTime): Boolean;
function ISODate(ADate: TDateTime): string;
procedure EncodeTask(const ATask: TTaskRecord; out ADisk: TTaskDiskRecord);
procedure DecodeTask(const ADisk: TTaskDiskRecord; out ATask: TTaskRecord);

implementation

function PriorityText(APriority: TPriority): string;
begin
  case APriority of
    prBaja: Result := 'Baja';
    prMedia: Result := 'Media';
    prAlta: Result := 'Alta';
  else
    Result := 'Desconocida';
  end;
end;

function StatusText(AStatus: TTaskStatus): string;
begin
  case AStatus of
    tsCreada: Result := 'Creada';
    tsPendiente: Result := 'Pendiente';
    tsEnTrabajo: Result := 'En trabajo';
    tsCompletada: Result := 'Completada';
  else
    Result := 'Desconocido';
  end;
end;

function StatusKey(AStatus: TTaskStatus): string;
begin
  case AStatus of
    tsCreada: Result := 'creada';
    tsPendiente: Result := 'pendiente';
    tsEnTrabajo: Result := 'trabajo';
    tsCompletada: Result := 'ok';
  else
    Result := '';
  end;
end;

function ParseStatus(const AText: string): TTaskStatus;
var
  S: string;
begin
  S := LowerCase(Trim(AText));
  if (S = 'creada') or (S = 'nueva') then
    Result := tsCreada
  else if (S = 'pendiente') or (S = 'plan') then
    Result := tsPendiente
  else if (S = 'trabajo') or (S = 'en-trabajo') or (S = 'en_trabajo') or
          (S = 'en trabajo') or (S = 'start') then
    Result := tsEnTrabajo
  else if (S = 'ok') or (S = 'completada') then
    Result := tsCompletada
  else
    raise Exception.CreateFmt('Estado no valido: %s (creada/pendiente/trabajo/ok).', [AText]);
end;

function ParsePriority(const AText: string): TPriority;
var
  S: string;
begin
  S := LowerCase(Trim(AText));
  if (S = '') or (S = 'media') or (S = 'm') then
    Result := prMedia
  else if (S = 'baja') or (S = 'b') then
    Result := prBaja
  else if (S = 'alta') or (S = 'a') then
    Result := prAlta
  else
    raise Exception.CreateFmt('Prioridad no valida: %s (baja/media/alta).', [AText]);
end;

function TryISODate(const AText: string; out ADate: TDateTime): Boolean;
var
  Y, M, D: Word;
  IY, IM, ID: Integer;
begin
  ADate := 0;
  Result := False;
  if Length(AText) <> 10 then Exit;
  if (AText[5] <> '-') or (AText[8] <> '-') then Exit;
  if (not TryStrToInt(Copy(AText, 1, 4), IY)) or
     (not TryStrToInt(Copy(AText, 6, 2), IM)) or
     (not TryStrToInt(Copy(AText, 9, 2), ID)) then Exit;
  if (IY < 1) or (IY > 9999) or (IM < 1) or (IM > 12) or
     (ID < 1) or (ID > 31) then Exit;
  Y := IY; M := IM; D := ID;
  Result := TryEncodeDate(Y, M, D, ADate);
end;

function ISODate(ADate: TDateTime): string;
begin
  if ADate = 0 then Result := '-'
  else Result := FormatDateTime('yyyy-mm-dd', ADate);
end;

procedure ValidateText(const AText, AField: string; AMaxBytes: Integer);
var
  I: Integer;
begin
  if (Length(AText) = 0) or (Length(AText) > AMaxBytes) then
    raise Exception.CreateFmt('%s debe tener entre 1 y %d bytes UTF-8.',
      [AField, AMaxBytes]);
  for I := 1 to Length(AText) do
    if AText[I] in [#0, #10, #13] then
      raise Exception.CreateFmt('%s no admite saltos de linea ni NUL.', [AField]);
end;

procedure EncodeTask(const ATask: TTaskRecord; out ADisk: TTaskDiskRecord);
begin
  ValidateText(ATask.Description, 'La descripcion', MAX_DESCRIPTION_BYTES);
  ValidateText(ATask.Category, 'La categoria', MAX_CATEGORY_BYTES);
  if ATask.ID <= 0 then raise Exception.Create('ID de tarea invalido.');
  FillChar(ADisk, SizeOf(ADisk), 0);
  ADisk.ID := ATask.ID;
  Move(ATask.Description[1], ADisk.Description[0], Length(ATask.Description));
  Move(ATask.Category[1], ADisk.Category[0], Length(ATask.Category));
  ADisk.CreatedAt := ATask.CreatedAt;
  ADisk.StartedAt := ATask.StartedAt;
  ADisk.CompletedAt := ATask.CompletedAt;
  ADisk.DueAt := ATask.DueAt;
  ADisk.Priority := Ord(ATask.Priority);
  ADisk.Status := Ord(ATask.Status);
end;

procedure DecodeTask(const ADisk: TTaskDiskRecord; out ATask: TTaskRecord);
var
  N, C: Integer;
begin
  if (ADisk.ID <= 0) or (ADisk.Priority > Ord(High(TPriority))) or
     (ADisk.Status > Ord(High(TTaskStatus))) then
    raise Exception.Create('Archivo corrupto: ID, prioridad o estado invalido.');
  N := 0;
  while (N < DESCRIPTION_CAPACITY) and (ADisk.Description[N] <> #0) do Inc(N);
  if (N = 0) or (N > MAX_DESCRIPTION_BYTES) then
    raise Exception.Create('Archivo corrupto: descripcion invalida.');
  C := 0;
  while (C < CATEGORY_CAPACITY) and (ADisk.Category[C] <> #0) do Inc(C);
  if (C = 0) or (C > MAX_CATEGORY_BYTES) then
    raise Exception.Create('Archivo corrupto: categoria invalida.');
  ATask.ID := ADisk.ID;
  SetString(ATask.Description, PAnsiChar(@ADisk.Description[0]), N);
  SetString(ATask.Category, PAnsiChar(@ADisk.Category[0]), C);
  ATask.CreatedAt := ADisk.CreatedAt;
  ATask.StartedAt := ADisk.StartedAt;
  ATask.CompletedAt := ADisk.CompletedAt;
  ATask.DueAt := ADisk.DueAt;
  ATask.Priority := TPriority(ADisk.Priority);
  ATask.Status := TTaskStatus(ADisk.Status);
end;

end.
