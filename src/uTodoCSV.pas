unit uTodoCSV;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  utodotypes, utodostore;

{ Exporta todas las tareas sin modificar el almacen binario. }
procedure ExportTasksCSV(AStore: TTodoStore; const AFileName: string);

implementation

uses
  SysUtils, BaseUnix, uTodoTypes;

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

end.
