{***************************************************}
{  TeeChart MCP Server                              }
{  Copyright (c) 2026 by Steema Software            }
{***************************************************}
program TeeChart_MCP;

{$APPTYPE CONSOLE}

// This project has been partially created using the AI

uses
  System.SysUtils,
  System.JSON,
  MCP.Transport,
  MCP.Server,
  MCP.Charts;

var
  Server: TMCPServer;

begin
  {$IFOPT D+}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}

  Server := TMCPServer.Create(TStdioTransport.Create, 'teechart-mcp', '0.1.0');
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

