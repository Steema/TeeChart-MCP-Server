{***************************************************}
{  TeeChart MCP Server                              }
{  Copyright (c) 2026 by Steema Software            }
{***************************************************}
program TeeChart_MCP;

{$APPTYPE CONSOLE}

// This project has been partially created using the AI

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  MCP.Transport,
  MCP.Transport.Http,
  MCP.Server,
  MCP.Charts;

function ParseArgs(out AUseHttp: Boolean; out APort: Integer): Boolean;
var
  I: Integer;
  Arg: string;
  Val: Integer;
begin
  AUseHttp := False;
  APort := 8080;
  Result := True;

  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);

    if SameText(Arg, '--help') or SameText(Arg, '-h') or
       SameText(Arg, '/?') or SameText(Arg, '-?') then
    begin
      Writeln('TeeChart MCP Server');
      Writeln('');
      Writeln('Usage:');
      Writeln('  TeeChart_MCP                 Run as stdio MCP server (default)');
      Writeln('  TeeChart_MCP --http [port]   Run as HTTP MCP server (default port: 8080)');
      Writeln('');
      Writeln('Options:');
      Writeln('  --http [port]   Start HTTP server on specified port (default 8080)');
      Writeln('  -p, --port <p>  Set the HTTP port');
      Writeln('  -h, --help      Show this help text');
      Result := False;
      Exit;
    end
    else if SameText(Arg, '--http') or SameText(Arg, '-http') or
            SameText(Arg, '/http') then
    begin
      AUseHttp := True;
      if (I < ParamCount) and TryStrToInt(ParamStr(I + 1), Val) then
      begin
        APort := Val;
        Inc(I);
      end;
    end
    else if StartsText('--http=', Arg) or StartsText('--http:', Arg) then
    begin
      AUseHttp := True;
      if TryStrToInt(Copy(Arg, 8, Length(Arg)), Val) then
        APort := Val;
    end
    else if SameText(Arg, '-p') or SameText(Arg, '--port') then
    begin
      AUseHttp := True;
      if (I < ParamCount) and TryStrToInt(ParamStr(I + 1), Val) then
      begin
        APort := Val;
        Inc(I);
      end;
    end;

    Inc(I);
  end;
end;

var
  Server: TMCPServer;
  Transport: ITransport;
  UseHttp: Boolean;
  Port: Integer;

begin
  {$IFOPT D+}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}

  if not ParseArgs(UseHttp, Port) then
    Exit;

  if UseHttp then
    Transport := THttpTransport.Create(Port)
  else
    Transport := TStdioTransport.Create;

  Server := TMCPServer.Create(Transport, 'teechart-mcp', '0.1.0');
  try
    Server.AddTool('echo', 'Returns the given text',
      '{"type":"object",' +
      '"properties":{"text":{"type":"string","description":"Text to echo"}},' +
      '"required":["text"]}',
      function(const Args: TJSONObject): TJSONArray
      begin
        Result := TJSONArray.Create;
        Result.Add(MCPText(Args.GetValue<string>('text', '')));
      end);

    RegisterChartTools(Server);

    Server.Run;
  finally
    Server.Free;
  end;
end.
