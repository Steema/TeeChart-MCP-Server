unit MCP.Charts;

{ TeeChart tools for the MCP server.

  Keeps the open charts in memory, indexed by id, and registers these tools:
    create_chart, add_series, set_title, set_axis_title, export_chart,
    delete_chart

  This is the ONLY unit that touches TeeChart. Define FMX in the project
  conditional defines to use FMXTee instead of VCLTee. }

interface

uses
  MCP.Server;

/// Registers all chart tools in the server
procedure RegisterChartTools(const Server: TMCPServer);

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.NetEncoding,
  System.Generics.Collections,

  {$IFDEF FMX}
  FMXTee.Engine, FMXTee.Procs, FMXTee.Series, FMXTee.Chart;
  {$ELSE}
  VCLTee.TeEngine, VCLTee.TeeProcs, VCLTee.Series, VCLTee.Chart,
  VCLTee.TeeExport, VCLTee.TeePNG, VCLTee.TeeJPEG,
  VCLTee.TeeSVGCanvas, VCLTee.TeePDFCanvas;
  {$ENDIF}

type
  TChartTools = class
  private
    FCharts: TObjectDictionary<string, TChart>;
    FNextId: Integer;

    function GetChart(const Args: TJSONObject): TChart;

    function CreateChart(const Args: TJSONObject): TJSONArray;
    function AddSeries(const Args: TJSONObject): TJSONArray;
    function SetTitle(const Args: TJSONObject): TJSONArray;
    function SetAxisTitle(const Args: TJSONObject): TJSONArray;
    function ExportChart(const Args: TJSONObject): TJSONArray;
    function DeleteChart(const Args: TJSONObject): TJSONArray;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Register(const Server: TMCPServer);
  end;

var
  GTools: TChartTools = nil;

{ ---------------- Argument helpers ---------------- }

function ArgStr(const Args: TJSONObject; const Name: string;
                const Default: string = ''): string;
begin
  if not Args.TryGetValue<string>(Name, Result) then
    Result := Default;
end;

function ArgInt(const Args: TJSONObject; const Name: string;
                const Default: Integer): Integer;
begin
  if not Args.TryGetValue<Integer>(Name, Result) then
    Result := Default;
end;

function ArgBool(const Args: TJSONObject; const Name: string;
                 const Default: Boolean): Boolean;
begin
  if not Args.TryGetValue<Boolean>(Name, Result) then
    Result := Default;
end;

function ArgDoubles(const Args: TJSONObject; const Name: string;
                    const Required: Boolean): TArray<Double>;
var
  V: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := nil;
  V := Args.GetValue(Name);

  if V = nil then
  begin
    if Required then
      raise EArgumentException.CreateFmt('Missing argument "%s"', [Name]);
    Exit;
  end;

  if not (V is TJSONArray) then
    raise EArgumentException.CreateFmt('"%s" must be an array', [Name]);

  Arr := TJSONArray(V);
  SetLength(Result, Arr.Count);

  for I := 0 to Arr.Count - 1 do
    if Arr.Items[I] is TJSONNumber then
      Result[I] := TJSONNumber(Arr.Items[I]).AsDouble
    else
      raise EArgumentException.CreateFmt('"%s"[%d] is not a number', [Name, I]);
end;

function ArgStrings(const Args: TJSONObject;
                    const Name: string): TArray<string>;
var
  V: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := nil;
  V := Args.GetValue(Name);

  if V = nil then
    Exit;

  if not (V is TJSONArray) then
    raise EArgumentException.CreateFmt('"%s" must be an array', [Name]);

  Arr := TJSONArray(V);
  SetLength(Result, Arr.Count);

  for I := 0 to Arr.Count - 1 do
    Result[I] := Arr.Items[I].Value;
end;

{ ---------------- TeeChart helpers ---------------- }

function SeriesClassFor(const AType: string): TChartSeriesClass;
begin
  if SameText(AType, 'line') then Result := TLineSeries
  else if SameText(AType, 'fastline') then Result := TFastLineSeries
  else if SameText(AType, 'bar') then Result := TBarSeries
  else if SameText(AType, 'horizbar') then Result := THorizBarSeries
  else if SameText(AType, 'area') then Result := TAreaSeries
  else if SameText(AType, 'pie') then Result := TPieSeries
  else if SameText(AType, 'points') then Result := TPointSeries
  else
    raise EArgumentException.CreateFmt(
      'Unknown series type "%s". Valid: line, fastline, bar, horizbar, ' +
      'area, pie, points', [AType]);
end;

function AxisByName(const Chart: TChart; const AName: string): TChartAxis;
begin
  if SameText(AName, 'left') then Result := Chart.LeftAxis
  else if SameText(AName, 'bottom') then Result := Chart.BottomAxis
  else if SameText(AName, 'right') then Result := Chart.RightAxis
  else if SameText(AName, 'top') then Result := Chart.TopAxis
  else
    raise EArgumentException.CreateFmt(
      'Unknown axis "%s". Valid: left, bottom, right, top', [AName]);
end;

{ Export. This is the part most likely to need adjusting to your TeeChart
  version (unit and export-format class names). Keep all of it here. }
procedure ExportToStream(const Chart: TChart; const Fmt: string;
                         const Stream: TStream);
{$IFDEF FMX}
begin
  // TODO: FMX export (e.g. via the FMX export formats or a TBitmap)
  raise ENotSupportedException.Create('Export is not implemented for FMX yet');
end;
{$ELSE}
var
  Exp: TTeeExportFormat;
begin
  if Fmt = 'png' then Exp := TPNGExportFormat.Create
  else if (Fmt = 'jpeg') or (Fmt = 'jpg') then Exp := TJPEGExportFormat.Create
  else if Fmt = 'svg' then Exp := TSVGExportFormat.Create
  else if Fmt = 'pdf' then Exp := TPDFExportFormat.Create
  else
    raise EArgumentException.CreateFmt(
      'Unsupported format "%s". Valid: png, jpeg, svg, pdf', [Fmt]);

  try
    Exp.Panel := Chart;
    Exp.SaveToStream(Stream);
  finally
    Exp.Free;
  end;
end;
{$ENDIF}

function StreamToBase64(const Stream: TMemoryStream): string;
var
  Enc: TBase64Encoding;
begin
  Enc := TBase64Encoding.Create(0, ''); // no line breaks
  try
    Result := Enc.EncodeBytesToString(Stream.Memory, Stream.Size);
  finally
    Enc.Free;
  end;
end;

function StreamToUtf8String(const Stream: TMemoryStream): string;
var
  B: TBytes;
begin
  SetLength(B, Stream.Size);
  Stream.Position := 0;
  Stream.ReadBuffer(B[0], Length(B));
  Result := TEncoding.UTF8.GetString(B);
end;

{ ---------------- TChartTools ---------------- }

constructor TChartTools.Create;
begin
  inherited Create;
  FCharts := TObjectDictionary<string, TChart>.Create([doOwnsValues]);
end;

destructor TChartTools.Destroy;
begin
  FCharts.Free;
  inherited;
end;

function TChartTools.GetChart(const Args: TJSONObject): TChart;
var
  Id: string;
begin
  Id := ArgStr(Args, 'chart_id');

  if not FCharts.TryGetValue(Id, Result) then
    raise EArgumentException.CreateFmt('Unknown chart_id "%s"', [Id]);
end;

function TChartTools.CreateChart(const Args: TJSONObject): TJSONArray;
var
  W, H: Integer;
  Title, Id: string;
  Chart: TChart;
begin
  W := ArgInt(Args, 'width', 800);
  H := ArgInt(Args, 'height', 500);

  if (W < 50) or (W > 8000) or (H < 50) or (H > 8000) then
    raise EArgumentException.Create('width and height must be between 50 and 8000');

  Title := ArgStr(Args, 'title');

  Chart := TChart.Create(nil);
  try
    Chart.Width := W;
    Chart.Height := H;
    Chart.View3D := ArgBool(Args, 'view3d', False);

    if Title = '' then
      Chart.Title.Visible := False
    else
      Chart.Title.Text.Text := Title;
  except
    Chart.Free;
    raise;
  end;

  Inc(FNextId);
  Id := 'chart' + FNextId.ToString;
  FCharts.Add(Id, Chart);

  Result := TJSONArray.Create;
  Result.Add(MCPText('chart_id: ' + Id));
end;

function TChartTools.AddSeries(const Args: TJSONObject): TJSONArray;
var
  Chart: TChart;
  SeriesClass: TChartSeriesClass;
  Values, Xs: TArray<Double>;
  Labels: TArray<string>;
  S: TChartSeries;
  Title, Lbl: string;
  I: Integer;
begin
  Chart := GetChart(Args);

  // Validate everything before touching the chart
  SeriesClass := SeriesClassFor(ArgStr(Args, 'type', 'line'));
  Values := ArgDoubles(Args, 'values', True);
  Xs := ArgDoubles(Args, 'x', False);
  Labels := ArgStrings(Args, 'labels');

  if (Length(Xs) > 0) and (Length(Xs) <> Length(Values)) then
    raise EArgumentException.Create('"x" and "values" must have the same length');

  if (Length(Labels) > 0) and (Length(Labels) <> Length(Values)) then
    raise EArgumentException.Create('"labels" and "values" must have the same length');

  S := Chart.AddSeries(SeriesClass);

  Title := ArgStr(Args, 'title');
  if Title <> '' then
    S.Title := Title;

  for I := 0 to High(Values) do
  begin
    if Length(Labels) > 0 then
      Lbl := Labels[I]
    else
      Lbl := '';

    if Length(Xs) > 0 then
      S.AddXY(Xs[I], Values[I], Lbl)
    else
      S.Add(Values[I], Lbl);
  end;

  Result := TJSONArray.Create;
  Result.Add(MCPText(Format('Series %d added (%d points)',
                            [Chart.SeriesCount - 1, Length(Values)])));
end;

function TChartTools.SetTitle(const Args: TJSONObject): TJSONArray;
var
  Chart: TChart;
  Sub: string;
begin
  Chart := GetChart(Args);

  Chart.Title.Text.Text := ArgStr(Args, 'title');
  Chart.Title.Visible := True;

  Sub := ArgStr(Args, 'subtitle');
  if Sub <> '' then
  begin
    Chart.SubTitle.Text.Text := Sub;
    Chart.SubTitle.Visible := True;
  end;

  Result := TJSONArray.Create;
  Result.Add(MCPText('Title updated'));
end;

function TChartTools.SetAxisTitle(const Args: TJSONObject): TJSONArray;
var
  Axis: TChartAxis;
begin
  Axis := AxisByName(GetChart(Args), ArgStr(Args, 'axis'));
  Axis.Title.Caption := ArgStr(Args, 'title');

  Result := TJSONArray.Create;
  Result.Add(MCPText('Axis title updated'));
end;

function TChartTools.ExportChart(const Args: TJSONObject): TJSONArray;
var
  Chart: TChart;
  Fmt, Path: string;
  Stream: TMemoryStream;
begin
  Chart := GetChart(Args);
  Fmt := LowerCase(ArgStr(Args, 'format', 'png'));
  Path := ArgStr(Args, 'path');

  // Without a path, the result must be returned inline
  if (Path = '') and (Fmt <> 'png') and (Fmt <> 'jpeg') and
     (Fmt <> 'jpg') and (Fmt <> 'svg') then
    raise EArgumentException.CreateFmt(
      '"path" is required for format "%s"', [Fmt]);

  Stream := TMemoryStream.Create;
  try
    ExportToStream(Chart, Fmt, Stream);

    if Stream.Size = 0 then
      raise Exception.Create('Export produced no data');

    Result := TJSONArray.Create;

    if Path <> '' then
    begin
      Stream.SaveToFile(Path);
      Result.Add(MCPText(Format('Saved %s (%d bytes)', [Path, Stream.Size])));
    end
    else
    if Fmt = 'png' then
      Result.Add(MCPImage(StreamToBase64(Stream), 'image/png'))
    else
    if (Fmt = 'jpeg') or (Fmt = 'jpg') then
      Result.Add(MCPImage(StreamToBase64(Stream), 'image/jpeg'))
    else
      Result.Add(MCPText(StreamToUtf8String(Stream))); // svg markup
  finally
    Stream.Free;
  end;
end;

function TChartTools.DeleteChart(const Args: TJSONObject): TJSONArray;
var
  Id: string;
begin
  Id := ArgStr(Args, 'chart_id');

  if not FCharts.ContainsKey(Id) then
    raise EArgumentException.CreateFmt('Unknown chart_id "%s"', [Id]);

  FCharts.Remove(Id); // frees the chart (doOwnsValues)

  Result := TJSONArray.Create;
  Result.Add(MCPText('Chart deleted'));
end;

procedure TChartTools.Register(const Server: TMCPServer);
begin
  Server.AddTool('create_chart',
    'Creates an empty chart and returns its chart_id',
    '{"type":"object","properties":{' +
    '"width":{"type":"integer","description":"Pixels, default 800"},' +
    '"height":{"type":"integer","description":"Pixels, default 500"},' +
    '"title":{"type":"string"},' +
    '"view3d":{"type":"boolean","description":"Default false"}}}',
    CreateChart);

  Server.AddTool('add_series',
    'Adds a series to a chart. Use "labels" for category charts (bar, pie) ' +
    'or "x" for numeric X values.',
    '{"type":"object","properties":{' +
    '"chart_id":{"type":"string"},' +
    '"type":{"type":"string","enum":["line","fastline","bar","horizbar",' +
    '"area","pie","points"],"description":"Default line"},' +
    '"values":{"type":"array","items":{"type":"number"}},' +
    '"labels":{"type":"array","items":{"type":"string"}},' +
    '"x":{"type":"array","items":{"type":"number"}},' +
    '"title":{"type":"string","description":"Series title (legend)"}},' +
    '"required":["chart_id","values"]}',
    AddSeries);

  Server.AddTool('set_title',
    'Sets the chart title and optional subtitle',
    '{"type":"object","properties":{' +
    '"chart_id":{"type":"string"},' +
    '"title":{"type":"string"},' +
    '"subtitle":{"type":"string"}},' +
    '"required":["chart_id","title"]}',
    SetTitle);

  Server.AddTool('set_axis_title',
    'Sets the title of an axis',
    '{"type":"object","properties":{' +
    '"chart_id":{"type":"string"},' +
    '"axis":{"type":"string","enum":["left","bottom","right","top"]},' +
    '"title":{"type":"string"}},' +
    '"required":["chart_id","axis","title"]}',
    SetAxisTitle);

  Server.AddTool('export_chart',
    'Exports the chart. Without "path", png/jpeg are returned as an image ' +
    'and svg as text. With "path", the file is saved to disk.',
    '{"type":"object","properties":{' +
    '"chart_id":{"type":"string"},' +
    '"format":{"type":"string","enum":["png","jpeg","svg","pdf"],' +
    '"description":"Default png"},' +
    '"path":{"type":"string","description":"Optional output file path"}},' +
    '"required":["chart_id"]}',
    ExportChart);

  Server.AddTool('delete_chart',
    'Frees a chart from memory',
    '{"type":"object","properties":{"chart_id":{"type":"string"}},' +
    '"required":["chart_id"]}',
    DeleteChart);
end;

{ ---------------- Public ---------------- }

procedure RegisterChartTools(const Server: TMCPServer);
begin
  if GTools = nil then
    GTools := TChartTools.Create;

  GTools.Register(Server);
end;

initialization

finalization
  GTools.Free;

end.
