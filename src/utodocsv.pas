unit utodocsv;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  utodotypes, utodostore;

{ Exporta todas las tareas sin modificar el almacen binario. }
procedure ExportTasksCSV(AStore: TTodoStore; const AFileName: string);
function ReadTasksCSV(const AFileName: string): TTaskArray;

implementation

uses
  SysUtils, BaseUnix, Classes;

const
  CSV_HEADER = 'id;descripcion;categoria;fecha_creacion;fecha_inicio;' +
    'fecha_finalizacion;fecha_vencimiento;prioridad;estado';

function CSVField(const AValue: string): string;
var
  I: Integer;
  NeedsQuotes: Boolean;
begin
  NeedsQuotes := False;
  Result := '';
  for I := 1 to Length(AValue) do
  begin
    if AValue[I] in [';', '"', #10, #13] then
      NeedsQuotes := True;
    if AValue[I] = '"' then
      Result := Result + '""'
    else
      Result := Result + AValue[I];
  end;
  if NeedsQuotes then
    Result := '"' + Result + '"';
end;

function CSVDateTime(ADate: TDateTime): string;
begin
  if ADate = 0 then
    Result := ''
  else
    Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"."zzz', ADate);
end;

function CSVRow(const ATask: TTaskRecord): string;
begin
  Result := IntToStr(ATask.ID) + ';' +
    CSVField(ATask.Description) + ';' +
    CSVField(ATask.Category) + ';' +
    CSVDateTime(ATask.CreatedAt) + ';' +
    CSVDateTime(ATask.StartedAt) + ';' +
    CSVDateTime(ATask.CompletedAt) + ';' +
    CSVDateTime(ATask.DueAt) + ';' +
    CSVField(LowerCase(PriorityText(ATask.Priority))) + ';' +
    CSVField(StatusKey(ATask.Status));
end;

procedure ExportTasksCSV(AStore: TTodoStore; const AFileName: string);
var
  F: TextFile;
  TempName, Dir: string;
  I: Integer;
  Opened: Boolean;
begin
  if Trim(AFileName) = '' then
    raise Exception.Create('Indica la ruta del archivo CSV.');
  if FileExists(AFileName) or DirectoryExists(AFileName) then
    raise Exception.CreateFmt('El destino ya existe: %s. No se sobrescribe.', [AFileName]);

  Dir := ExtractFileDir(ExpandFileName(AFileName));
  if not DirectoryExists(Dir) then
    raise Exception.CreateFmt('El directorio de destino no existe: %s.', [Dir]);

  TempName := AFileName + '.tmp';
  if FileExists(TempName) or DirectoryExists(TempName) then
    raise Exception.CreateFmt('Existe el archivo temporal %s. No se sobrescribe.', [TempName]);

  Opened := False;
  try
    AssignFile(F, TempName);
    Rewrite(F);
    Opened := True;
    try
      Writeln(F, CSV_HEADER);
      for I := 0 to AStore.Count - 1 do
        Writeln(F, CSVRow(AStore.Item(I)));
    finally
      CloseFile(F);
      Opened := False;
    end;

    { Al publicar solo un archivo completo, no dejamos CSV truncados. }
    if FileExists(AFileName) or DirectoryExists(AFileName) then
      raise Exception.CreateFmt('El destino ya existe: %s. No se sobrescribe.', [AFileName]);
    if fpRename(PChar(TempName), PChar(AFileName)) <> 0 then
      raise Exception.CreateFmt('No se pudo publicar el CSV: %s.', [AFileName]);
  except
    if Opened then
      CloseFile(F);
    DeleteFile(TempName);
    raise;
  end;
end;


{ Parser CSV delimitado por punto y coma. Respeta comillas dobles y CRLF/LF.
  Los saltos de linea dentro de campos se reconocen y luego EncodeTask
  los rechaza, porque tasks.dat no admite saltos de linea en los textos. }
function ReadTasksCSV(const AFileName: string): TTaskArray;
const
  MAX_CSV_BYTES = 20 * 1024 * 1024;
  MAX_CSV_ROWS = 10000;
var
  Stream: TFileStream;
  Content, Field: string;
  Fields: array of string;
  Position, RowNumber, FieldCount: Integer;
  State: (csStart, csPlain, csQuoted, csAfterQuote);
  Ch: Char;
  Task: TTaskRecord;
  Tasks: TTaskArray;
  Disk: TTaskDiskRecord;

  procedure PushField;
  begin
    SetLength(Fields, FieldCount + 1);
    Fields[FieldCount] := Field;
    Inc(FieldCount);
    Field := '';
  end;

  function ParseDateTime(const S, Name: string): TDateTime;
  var
    Y, M, D, H, N, Sec, MS, J: Integer;
    DPart, TPart: TDateTime;
  begin
    Result := 0;
    if S = '' then Exit;
    if (Length(S) <> 23) or (S[5] <> '-') or (S[8] <> '-') or
       (S[11] <> 'T') or (S[14] <> ':') or (S[17] <> ':') or
       (S[20] <> '.') then
      raise Exception.CreateFmt('%s debe tener formato AAAA-MM-DDThh:mm:ss.zzz.', [Name]);
    for J := 1 to Length(S) do
      if (J <> 5) and (J <> 8) and (J <> 11) and (J <> 14) and
         (J <> 17) and (J <> 20) and not (S[J] in ['0'..'9']) then
        raise Exception.CreateFmt('Caracter invalido en %s.', [Name]);
    Y := StrToInt(Copy(S, 1, 4));
    M := StrToInt(Copy(S, 6, 2));
    D := StrToInt(Copy(S, 9, 2));
    H := StrToInt(Copy(S, 12, 2));
    N := StrToInt(Copy(S, 15, 2));
    Sec := StrToInt(Copy(S, 18, 2));
    MS := StrToInt(Copy(S, 21, 3));
    if not TryEncodeDate(Y, M, D, DPart) or
       not TryEncodeTime(H, N, Sec, MS, TPart) then
      raise Exception.CreateFmt('Valor de fecha/hora invalido en %s.', [Name]);
    Result := DPart + TPart;
  end;

  procedure PushRow;
  var
    ParsedID: LongInt;
  begin
    Inc(RowNumber);
    if FieldCount <> 9 then
      raise Exception.CreateFmt('Fila %d: se esperaban 9 columnas, hay %d.',
        [RowNumber, FieldCount]);
    if RowNumber = 1 then
    begin
      if (Fields[0] <> 'id') or (Fields[1] <> 'descripcion') or
         (Fields[2] <> 'categoria') or (Fields[3] <> 'fecha_creacion') or
         (Fields[4] <> 'fecha_inicio') or
         (Fields[5] <> 'fecha_finalizacion') or
         (Fields[6] <> 'fecha_vencimiento') or
         (Fields[7] <> 'prioridad') or (Fields[8] <> 'estado') then
        raise Exception.Create('Cabecera CSV incompatible con la exportacion de todo.');
    end
    else
    begin
      if Length(Tasks) >= MAX_CSV_ROWS then
        raise Exception.Create('Se supero el maximo de filas CSV permitido.');
      if not TryStrToInt(Fields[0], ParsedID) or (ParsedID < 1) then
        raise Exception.CreateFmt('Fila %d: ID de origen invalido.', [RowNumber]);
      Task.ID := ParsedID; { ID solo para validar; el almacen lo reasigna. }
      Task.Description := Fields[1];
      Task.Category := Fields[2];
      Task.CreatedAt := ParseDateTime(Fields[3], 'fecha_creacion');
      Task.StartedAt := ParseDateTime(Fields[4], 'fecha_inicio');
      Task.CompletedAt := ParseDateTime(Fields[5], 'fecha_finalizacion');
      Task.DueAt := ParseDateTime(Fields[6], 'fecha_vencimiento');
      if Task.CreatedAt = 0 then
        raise Exception.CreateFmt('Fila %d: fecha_creacion obligatoria.', [RowNumber]);
      if (Fields[7] <> 'baja') and (Fields[7] <> 'media') and
         (Fields[7] <> 'alta') then
        raise Exception.CreateFmt('Fila %d: prioridad invalida.', [RowNumber]);
      Task.Priority := ParsePriority(Fields[7]);
      if (Fields[8] <> 'creada') and (Fields[8] <> 'pendiente') and
         (Fields[8] <> 'trabajo') and (Fields[8] <> 'ok') then
        raise Exception.CreateFmt('Fila %d: estado invalido.', [RowNumber]);
      Task.Status := ParseStatus(Fields[8]);
      if (Task.Status = tsCompletada) <> (Task.CompletedAt <> 0) then
        raise Exception.CreateFmt('Fila %d: fecha_finalizacion incompatible con el estado.', [RowNumber]);
      if (Task.Status = tsEnTrabajo) and (Task.StartedAt = 0) then
        raise Exception.CreateFmt('Fila %d: falta fecha_inicio para EN TRABAJO.', [RowNumber]);
      try
        EncodeTask(Task, Disk);
      except
        on E: Exception do
          raise Exception.CreateFmt('Fila %d: %s', [RowNumber, E.Message]);
      end;
      SetLength(Tasks, Length(Tasks) + 1);
      Tasks[High(Tasks)] := Task;
    end;
    SetLength(Fields, 0);
    FieldCount := 0;
  end;

  procedure EndRow;
  begin
    PushField;
    PushRow;
    State := csStart;
  end;

begin
  SetLength(Tasks, 0);
  if not FileExists(AFileName) then
    raise Exception.CreateFmt('No existe el CSV: %s.', [AFileName]);
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    if Stream.Size > MAX_CSV_BYTES then
      raise Exception.Create('CSV demasiado grande (maximo 20 MiB).');
    SetLength(Content, Integer(Stream.Size));
    if Stream.Size > 0 then Stream.ReadBuffer(Content[1], Length(Content));
  finally
    Stream.Free;
  end;
  if Content = '' then raise Exception.Create('CSV vacio.');
  { UTF-8 con BOM no forma parte de la cabecera del formato exportado. }
  if Copy(Content, 1, 3) = #$EF#$BB#$BF then Delete(Content, 1, 3);
  RowNumber := 0;
  FieldCount := 0;
  Field := '';
  State := csStart;
  Position := 1;
  while Position <= Length(Content) do
  begin
    Ch := Content[Position];
    case State of
      csStart:
        case Ch of
          '"': State := csQuoted;
          ';': PushField;
          #10, #13: EndRow;
        else
          Field := Field + Ch;
          State := csPlain;
        end;
      csPlain:
        case Ch of
          ';': begin PushField; State := csStart; end;
          #10, #13: EndRow;
          '"': raise Exception.CreateFmt('Fila %d: comillas CSV mal ubicadas.', [RowNumber + 1]);
        else
          Field := Field + Ch;
        end;
      csQuoted:
        if Ch = '"' then State := csAfterQuote
        else Field := Field + Ch;
      csAfterQuote:
        case Ch of
          '"': begin Field := Field + '"'; State := csQuoted; end;
          ';': begin PushField; State := csStart; end;
          #10, #13: EndRow;
        else
          raise Exception.CreateFmt('Fila %d: texto inesperado despues de comillas.', [RowNumber + 1]);
        end;
    end;
    if (Ch = #13) and (State = csStart) and
       (Position < Length(Content)) and (Content[Position + 1] = #10) then
      Inc(Position);
    Inc(Position);
  end;
  if State = csQuoted then
    raise Exception.Create('CSV con campo entrecomillado sin cerrar.');
  if (State <> csStart) or (FieldCount > 0) or (Field <> '') then
    EndRow;
  if RowNumber = 0 then raise Exception.Create('CSV sin cabecera.');
  Result := Tasks;
end;

end.
