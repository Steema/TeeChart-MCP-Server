program TeeChart_MCP;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.JSON,
  MCP.Transport,
  MCP.Server;

var
  Server: TMCPServer;

begin
  {$IFOPT D+}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}

  Server := TMCPServer.Create(TStdioTransport.Create, 'teechart-mcp', '0.1.0');
  try
    // Sample tool to validate the core. Replace with TeeChart tools later.
    Server.AddTool('echo', 'Returns the given text',
      '{"type":"object",' +
      '"properties":{"text":{"type":"string","description":"Text to echo"}},' +
      '"required":["text"]}',
      function(const Args: TJSONObject): TJSONArray
      begin
        Result := TJSONArray.Create;
        Result.Add(MCPText(Args.GetValue<string>('text', '')));
      end);

    Server.Run;
  finally
    Server.Free;
  end;
end.

