{***************************************************}
{  TeeChart MCP Server                              }
{  Copyright (c) 2026 by Steema Software            }
{***************************************************}
unit MCP.Transport.Http;

{ HTTP transport for the MCP server.

  Implements both the MCP Streamable HTTP transport (spec 2025-03-26) and the
  legacy HTTP+SSE transport (spec 2024-11-05) on the /mcp endpoint:

    POST /mcp  – client sends a JSON-RPC request.
                 * If the client sends  Accept: text/event-stream  the server
                   responds with a single-event SSE body (Streamable HTTP).
                 * Otherwise the response is application/json.
                 * For notifications (no id), returns 202 Accepted.

    GET  /mcp  – opens a persistent SSE channel (legacy 2024-11-05 transport).
                 Sends the initial "endpoint" event with URI "/mcp".
                 Server-initiated messages and responses are pushed here.

    OPTIONS /mcp – CORS preflight (204 No Content).

  Select the HTTP transport with the --http [port] command-line flag.
  Omitting the flag keeps the default stdio transport. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs,
  System.Generics.Collections,
  IdHTTPServer, IdCustomHTTPServer, IdContext, IdGlobal,
  MCP.Transport;

type
  TResponseWaiter = class
  public
    Event: TEvent;
    Response: string;
    constructor Create;
    destructor Destroy; override;
  end;

  /// MCP HTTP transport backed by Indy TIdHTTPServer.
  THttpTransport = class(TInterfacedObject, ITransport)
  private
    FServer    : TIdHTTPServer;
    FPort      : Integer;
    FShutdown  : Boolean;

    // Inbound queue: HTTP handler threads push JSON-RPC lines;
    // the MCP message loop pops them via ReadMessage.
    FInQueue   : TThreadedQueue<string>;

    // SSE clients (legacy GET transport)
    FSSELock   : TCriticalSection;
    FSSEClients: TList<TIdContext>;

    // Response synchronization: POST handler waits on a TEvent;
    // WriteMessage sets the response and signals the event.
    FRespLock  : TCriticalSection;
    FWaiters   : TDictionary<string, TResponseWaiter>;

    function  ExtractId(const Json: string): string;
    procedure PushSSE(const Msg: string);

    procedure RegisterSSEClient(AContext: TIdContext);
    procedure UnregisterSSEClient(AContext: TIdContext);

    // Indy callback
    procedure OnRequest(AContext: TIdContext;
                        ARequestInfo: TIdHTTPRequestInfo;
                        AResponseInfo: TIdHTTPResponseInfo);

    procedure DoOptions(AResponseInfo: TIdHTTPResponseInfo);
    procedure DoGet    (AContext: TIdContext;
                        ARequestInfo: TIdHTTPRequestInfo;
                        AResponseInfo: TIdHTTPResponseInfo);
    procedure DoPost   (AContext: TIdContext;
                        ARequestInfo: TIdHTTPRequestInfo;
                        AResponseInfo: TIdHTTPResponseInfo);

    procedure AddCORS(AResponseInfo: TIdHTTPResponseInfo);
    function  ReadBody(ARequestInfo: TIdHTTPRequestInfo): string;
  public
    constructor Create(APort: Integer = 8080);
    destructor  Destroy; override;

    procedure Shutdown;

    // ITransport
    function  ReadMessage(out Msg: string): Boolean;
    procedure WriteMessage(const Msg: string);
    procedure Log(const Msg: string);

    property Port: Integer read FPort;
  end;

implementation

uses
  System.JSON;

{ TResponseWaiter }

constructor TResponseWaiter.Create;
begin
  inherited Create;
  Event := TEvent.Create(nil, True, False, '');
  Response := '';
end;

destructor TResponseWaiter.Destroy;
begin
  Event.Free;
  inherited;
end;

{ ------------------------------------------------------------------ }
{ THttpTransport                                                       }
{ ------------------------------------------------------------------ }

constructor THttpTransport.Create(APort: Integer);
begin
  inherited Create;
  FPort     := APort;
  FShutdown := False;

  FInQueue := TThreadedQueue<string>.Create(1024, INFINITE, 1000);

  FSSELock    := TCriticalSection.Create;
  FSSEClients := TList<TIdContext>.Create;

  FRespLock := TCriticalSection.Create;
  FWaiters  := TDictionary<string, TResponseWaiter>.Create;

  FServer                := TIdHTTPServer.Create(nil);
  FServer.DefaultPort    := FPort;
  FServer.OnCommandGet   := OnRequest;
  FServer.OnCommandOther := OnRequest;
  FServer.KeepAlive      := False;
  FServer.Active         := True;

  Writeln(ErrOutput,
    Format('[HTTP] MCP server listening on http://localhost:%d/mcp', [FPort]));
end;

destructor THttpTransport.Destroy;
begin
  Shutdown;
  FServer.Active := False;
  FServer.Free;

  FRespLock.Acquire;
  try
    FWaiters.Free;
  finally
    FRespLock.Release;
  end;
  FRespLock.Free;

  FSSELock.Acquire;
  try
    FSSEClients.Free;
  finally
    FSSELock.Release;
  end;
  FSSELock.Free;

  FInQueue.Free;
  inherited;
end;

procedure THttpTransport.Shutdown;
begin
  FShutdown := True;
  FInQueue.DoShutDown;
end;

{ ------------------------------------------------------------------ }
{ SSE client registration                                              }
{ ------------------------------------------------------------------ }

procedure THttpTransport.RegisterSSEClient(AContext: TIdContext);
begin
  FSSELock.Acquire;
  try
    FSSEClients.Add(AContext);
  finally
    FSSELock.Release;
  end;
end;

procedure THttpTransport.UnregisterSSEClient(AContext: TIdContext);
begin
  FSSELock.Acquire;
  try
    FSSEClients.Remove(AContext);
  finally
    FSSELock.Release;
  end;
end;

procedure THttpTransport.PushSSE(const Msg: string);
var
  I: Integer;
  Ctx: TIdContext;
  Frame: string;
begin
  FSSELock.Acquire;
  try
    if FSSEClients.Count = 0 then Exit;

    Frame := 'event: message'#10'data: ' + Msg + #10#10;
    for I := FSSEClients.Count - 1 downto 0 do
    begin
      Ctx := FSSEClients[I];
      try
        if Ctx.Connection.Connected then
          Ctx.Connection.IOHandler.Write(Frame, IndyTextEncoding_UTF8)
        else
          FSSEClients.Delete(I);
      except
        FSSEClients.Delete(I);
      end;
    end;
  finally
    FSSELock.Release;
  end;
end;

{ ------------------------------------------------------------------ }
{ CORS helper                                                          }
{ ------------------------------------------------------------------ }

procedure THttpTransport.AddCORS(AResponseInfo: TIdHTTPResponseInfo);
begin
  with AResponseInfo.CustomHeaders do
  begin
    Values['Access-Control-Allow-Origin']  := '*';
    Values['Access-Control-Allow-Methods'] := 'GET, POST, OPTIONS';
    Values['Access-Control-Allow-Headers'] :=
      'Content-Type, Accept, Authorization, Mcp-Session-Id';
    Values['Access-Control-Expose-Headers'] := 'Mcp-Session-Id';
  end;
end;

{ ------------------------------------------------------------------ }
{ Request body helper                                                  }
{ ------------------------------------------------------------------ }

function THttpTransport.ReadBody(ARequestInfo: TIdHTTPRequestInfo): string;
var
  Bytes: TBytes;
  Len  : Int64;
begin
  Result := '';
  if ARequestInfo.PostStream = nil then Exit;
  Len := ARequestInfo.PostStream.Size - ARequestInfo.PostStream.Position;
  if Len <= 0 then Exit;
  SetLength(Bytes, Len);
  ARequestInfo.PostStream.ReadBuffer(Bytes[0], Len);
  Result := TEncoding.UTF8.GetString(Bytes);
end;

{ ------------------------------------------------------------------ }
{ JSON-RPC id extractor                                                }
{ ------------------------------------------------------------------ }

function THttpTransport.ExtractId(const Json: string): string;
var
  V: TJSONValue;
  Obj: TJSONObject;
  Id: TJSONValue;
begin
  Result := '';
  V := TJSONObject.ParseJSONValue(Json);
  if V = nil then Exit;
  try
    if V is TJSONObject then
    begin
      Obj := TJSONObject(V);
      Id := Obj.GetValue('id');
      if Id <> nil then
        Result := Id.ToJSON;
    end;
  finally
    V.Free;
  end;
end;

{ ------------------------------------------------------------------ }
{ Top-level dispatcher                                                 }
{ ------------------------------------------------------------------ }

procedure THttpTransport.OnRequest(AContext: TIdContext;
                                   ARequestInfo: TIdHTTPRequestInfo;
                                   AResponseInfo: TIdHTTPResponseInfo);
var
  Path: string;
begin
  AddCORS(AResponseInfo);

  // CORS preflight
  if ARequestInfo.CommandType = hcOPTION then
  begin
    DoOptions(AResponseInfo);
    Exit;
  end;

  // Normalize path
  Path := ARequestInfo.Document;
  while (Length(Path) > 1) and (Path[High(Path)] = '/') do
    Delete(Path, High(Path), 1);

  if (Path <> '/mcp') and (Path <> '/sse') then
  begin
    AResponseInfo.ResponseNo  := 404;
    AResponseInfo.ContentType := 'text/plain';
    AResponseInfo.ContentText := 'Not found. MCP endpoint is at /mcp';
    Exit;
  end;

  case ARequestInfo.CommandType of
    hcGET  : DoGet (AContext, ARequestInfo, AResponseInfo);
    hcPOST : DoPost(AContext, ARequestInfo, AResponseInfo);
  else
    AResponseInfo.ResponseNo  := 405;
    AResponseInfo.ContentType := 'text/plain';
    AResponseInfo.ContentText := 'Method not allowed';
  end;
end;

{ ------------------------------------------------------------------ }
{ OPTIONS (CORS preflight)                                             }
{ ------------------------------------------------------------------ }

procedure THttpTransport.DoOptions(AResponseInfo: TIdHTTPResponseInfo);
begin
  AResponseInfo.ResponseNo  := 204;
  AResponseInfo.ContentText := '';
end;

{ ------------------------------------------------------------------ }
{ GET /mcp  – legacy persistent SSE channel                            }
{ ------------------------------------------------------------------ }

procedure THttpTransport.DoGet(AContext: TIdContext;
                               ARequestInfo: TIdHTTPRequestInfo;
                               AResponseInfo: TIdHTTPResponseInfo);
var
  Accept: string;
begin
  Accept := ARequestInfo.Accept;
  if Pos('text/event-stream', Accept) = 0 then
  begin
    AResponseInfo.ResponseNo  := 400;
    AResponseInfo.ContentType := 'text/plain';
    AResponseInfo.ContentText :=
      'GET /mcp requires Accept: text/event-stream';
    Exit;
  end;

  AResponseInfo.ResponseNo  := 200;
  AResponseInfo.ContentType := 'text/event-stream; charset=utf-8';
  AResponseInfo.CloseConnection := False;
  with AResponseInfo.CustomHeaders do
  begin
    Values['Cache-Control']     := 'no-cache';
    Values['X-Accel-Buffering'] := 'no';
    Values['Connection']        := 'keep-alive';
  end;

  // Flush headers immediately
  AResponseInfo.WriteHeader;

  // Send the endpoint event for MCP 2024-11-05 spec
  try
    AContext.Connection.IOHandler.Write('event: endpoint'#10'data: /mcp'#10#10,
                                        IndyTextEncoding_UTF8);
  except
    Exit;
  end;

  RegisterSSEClient(AContext);
  try
    while not FShutdown and AContext.Connection.Connected do
      Sleep(200);
  finally
    UnregisterSSEClient(AContext);
  end;
end;

{ ------------------------------------------------------------------ }
{ POST /mcp  – JSON-RPC request from client                            }
{ ------------------------------------------------------------------ }

procedure THttpTransport.DoPost(AContext: TIdContext;
                                ARequestInfo: TIdHTTPRequestInfo;
                                AResponseInfo: TIdHTTPResponseInfo);
const
  ResponseTimeout = 30000; // ms
var
  Body    : string;
  WantSSE : Boolean;
  ReqId   : string;
  Waiter  : TResponseWaiter;
  Found   : Boolean;
  Resp    : string;
begin
  Body := ReadBody(ARequestInfo).Trim;
  if Body = '' then
  begin
    AResponseInfo.ResponseNo  := 400;
    AResponseInfo.ContentType := 'text/plain';
    AResponseInfo.ContentText := 'Empty request body';
    Exit;
  end;

  WantSSE := Pos('text/event-stream', ARequestInfo.Accept) > 0;
  ReqId   := ExtractId(Body);

  // For notifications (no id) enqueue and return immediately
  if ReqId = '' then
  begin
    FInQueue.PushItem(Body);
    AResponseInfo.ResponseNo  := 202;
    AResponseInfo.ContentText := '';
    Exit;
  end;

  // Register waiter before enqueuing to prevent race condition
  Waiter := TResponseWaiter.Create;
  try
    FRespLock.Acquire;
    try
      FWaiters.AddOrSetValue(ReqId, Waiter);
    finally
      FRespLock.Release;
    end;

    FInQueue.PushItem(Body);

    Found := Waiter.Event.WaitFor(ResponseTimeout) = wrSignaled;
    if Found then
      Resp := Waiter.Response;
  finally
    FRespLock.Acquire;
    try
      FWaiters.Remove(ReqId);
    finally
      FRespLock.Release;
    end;
    Waiter.Free;
  end;

  if not Found then
  begin
    AResponseInfo.ResponseNo  := 408;
    AResponseInfo.ContentType := 'text/plain';
    AResponseInfo.ContentText := 'MCP request timed out';
    Exit;
  end;

  if WantSSE then
  begin
    // Streamable HTTP: single-event SSE body
    AResponseInfo.ResponseNo  := 200;
    AResponseInfo.ContentType := 'text/event-stream; charset=utf-8';
    AResponseInfo.CustomHeaders.Values['Cache-Control'] := 'no-cache';
    AResponseInfo.ContentText :=
      'event: message'#10 + 'data: ' + Resp + #10 + #10;
  end
  else
  begin
    // Plain JSON
    AResponseInfo.ResponseNo  := 200;
    AResponseInfo.ContentType := 'application/json; charset=utf-8';
    AResponseInfo.ContentText := Resp;
  end;
end;

{ ------------------------------------------------------------------ }
{ ITransport                                                           }
{ ------------------------------------------------------------------ }

function THttpTransport.ReadMessage(out Msg: string): Boolean;
var
  WR: TWaitResult;
begin
  Msg := '';
  repeat
    WR := FInQueue.PopItem(Msg);
    if WR = wrSignaled then
    begin
      Result := True;
      Exit;
    end;
  until FShutdown;
  Result := False;
end;

procedure THttpTransport.WriteMessage(const Msg: string);
var
  ReqId: string;
  Waiter: TResponseWaiter;
begin
  // Legacy SSE push
  PushSSE(Msg);

  // Signal waiting POST thread
  ReqId := ExtractId(Msg);
  if ReqId <> '' then
  begin
    FRespLock.Acquire;
    try
      if FWaiters.TryGetValue(ReqId, Waiter) then
      begin
        Waiter.Response := Msg;
        Waiter.Event.SetEvent;
      end;
    finally
      FRespLock.Release;
    end;
  end;
end;

procedure THttpTransport.Log(const Msg: string);
begin
  Writeln(ErrOutput, '[HTTP] ' + Msg);
end;

end.
