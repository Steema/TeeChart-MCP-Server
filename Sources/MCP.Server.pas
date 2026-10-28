{***************************************************}
{  TeeChart MCP Server                              }
{  Copyright (c) 2026 by Steema Software            }
{***************************************************}
unit MCP.Server;

{ Minimal MCP server core (JSON-RPC 2.0).
  Supports: initialize, notifications/*, ping, tools/list, tools/call.
  Only depends on the RTL (System.JSON), so it is cross-platform. }

interface

uses
  System.SysUtils, System.JSON, System.Generics.Collections,
  MCP.Transport;

type
  /// A tool handler receives the call arguments (never nil) and returns
  /// the MCP "content" array (ownership passes to the server).
  /// Raise an exception to report a tool error (isError = true).
  TMCPToolHandler = reference to function(const Args: TJSONObject): TJSONArray;

  TMCPTool = class
  public
    Name: string;
    Description: string;
    InputSchema: TJSONObject; // owned
    Handler: TMCPToolHandler;
    destructor Destroy; override;
  end;

  TMCPServer = class
  private
    FTransport: ITransport;
    FName: string;
    FVersion: string;
    FTools: TObjectList<TMCPTool>;

    function FindTool(const AName: string): TMCPTool;

    procedure SendResult(const Id: TJSONValue; const AResult: TJSONObject);
    procedure SendError(const Id: TJSONValue; const Code: Integer;
                        const Msg: string);

    procedure HandleMessage(const Line: string);
    function HandleInitialize(const Params: TJSONValue): TJSONObject;
    function HandleToolsList: TJSONObject;
    function HandleToolsCall(const Params: TJSONValue): TJSONObject;
  public
    constructor Create(const ATransport: ITransport;
                       const AName, AVersion: string);
    destructor Destroy; override;

    /// SchemaJson: JSON Schema of the arguments, as a JSON string.
    procedure AddTool(const AName, ADescription, SchemaJson: string;
                      const AHandler: TMCPToolHandler);

    /// Message loop. Returns when the transport is closed.
    procedure Run;
  end;

/// Helpers to build tool results
function MCPText(const S: string): TJSONObject;
function MCPImage(const Base64Data, MimeType: string): TJSONObject;

implementation

const
  DefaultProtocolVersion = '2025-03-26';

  ERR_PARSE            = -32700;
  ERR_INVALID_REQUEST  = -32600;
  ERR_METHOD_NOT_FOUND = -32601;
  ERR_INVALID_PARAMS   = -32602;
  ERR_INTERNAL         = -32603;

type
  EMCPError = class(Exception)
  public
    Code: Integer;
    constructor Create(const ACode: Integer; const Msg: string);
  end;

constructor EMCPError.Create(const ACode: Integer; const Msg: string);
begin
  inherited Create(Msg);
  Code := ACode;
end;

function MCPText(const S: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'text');
  Result.AddPair('text', S);
end;

function MCPImage(const Base64Data, MimeType: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'image');
  Result.AddPair('data', Base64Data);
  Result.AddPair('mimeType', MimeType);
end;

{ TMCPTool }

destructor TMCPTool.Destroy;
begin
  InputSchema.Free;
  inherited;
end;

{ TMCPServer }

constructor TMCPServer.Create(const ATransport: ITransport;
                              const AName, AVersion: string);
begin
  inherited Create;
  FTransport := ATransport;
  FName := AName;
  FVersion := AVersion;
  FTools := TObjectList<TMCPTool>.Create(True);
end;

destructor TMCPServer.Destroy;
begin
  FTools.Free;
  inherited;
end;

procedure TMCPServer.AddTool(const AName, ADescription, SchemaJson: string;
                             const AHandler: TMCPToolHandler);
var
  Tool: TMCPTool;
  Schema: TJSONValue;
begin
  Schema := TJSONObject.ParseJSONValue(SchemaJson);

  if not (Schema is TJSONObject) then
  begin
    Schema.Free;
    raise EArgumentException.CreateFmt('Invalid input schema for tool "%s"',
                                       [AName]);
  end;

  Tool := TMCPTool.Create;
  Tool.Name := AName;
  Tool.Description := ADescription;
  Tool.InputSchema := TJSONObject(Schema);
  Tool.Handler := AHandler;

  FTools.Add(Tool);
end;

function TMCPServer.FindTool(const AName: string): TMCPTool;
var
  Tool: TMCPTool;
begin
  for Tool in FTools do
    if Tool.Name = AName then
      Exit(Tool);

  Result := nil;
end;

procedure TMCPServer.SendResult(const Id: TJSONValue;
                                const AResult: TJSONObject);
var
  Resp: TJSONObject;
begin
  Resp := TJSONObject.Create;
  try
    Resp.AddPair('jsonrpc', '2.0');

    if Id = nil then
      Resp.AddPair('id', TJSONNull.Create)
    else
      Resp.AddPair('id', Id.Clone as TJSONValue);

    Resp.AddPair('result', AResult); // Resp takes ownership

    FTransport.WriteMessage(Resp.ToJSON);
  finally
    Resp.Free;
  end;
end;

procedure TMCPServer.SendError(const Id: TJSONValue; const Code: Integer;
                               const Msg: string);
var
  Resp, Err: TJSONObject;
begin
  Resp := TJSONObject.Create;
  try
    Resp.AddPair('jsonrpc', '2.0');

    if Id = nil then
      Resp.AddPair('id', TJSONNull.Create)
    else
      Resp.AddPair('id', Id.Clone as TJSONValue);

    Err := TJSONObject.Create;
    Err.AddPair('code', TJSONNumber.Create(Code));
    Err.AddPair('message', Msg);
    Resp.AddPair('error', Err);

    FTransport.WriteMessage(Resp.ToJSON);
  finally
    Resp.Free;
  end;
end;

function TMCPServer.HandleInitialize(const Params: TJSONValue): TJSONObject;
var
  Version: string;
  Caps, ToolsCap, Info: TJSONObject;
begin
  // Echo the client's protocol version when provided
  Version := DefaultProtocolVersion;
  if Params is TJSONObject then
    TJSONObject(Params).TryGetValue<string>('protocolVersion', Version);

  Result := TJSONObject.Create;
  Result.AddPair('protocolVersion', Version);

  Caps := TJSONObject.Create;
  ToolsCap := TJSONObject.Create;
  Caps.AddPair('tools', ToolsCap);
  Result.AddPair('capabilities', Caps);

  Info := TJSONObject.Create;
  Info.AddPair('name', FName);
  Info.AddPair('version', FVersion);
  Result.AddPair('serverInfo', Info);
end;

function TMCPServer.HandleToolsList: TJSONObject;
var
  Tool: TMCPTool;
  Tools: TJSONArray;
  Item: TJSONObject;
begin
  Tools := TJSONArray.Create;

  for Tool in FTools do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('name', Tool.Name);
    Item.AddPair('description', Tool.Description);
    Item.AddPair('inputSchema', Tool.InputSchema.Clone as TJSONObject);
    Tools.Add(Item);
  end;

  Result := TJSONObject.Create;
  Result.AddPair('tools', Tools);
end;

function TMCPServer.HandleToolsCall(const Params: TJSONValue): TJSONObject;
var
  P: TJSONObject;
  ToolName: string;
  Tool: TMCPTool;
  ArgsValue: TJSONValue;
  Args: TJSONObject;
  OwnsArgs, IsError: Boolean;
  Content: TJSONArray;
begin
  if not (Params is TJSONObject) then
    raise EMCPError.Create(ERR_INVALID_PARAMS, 'Missing params');

  P := TJSONObject(Params);

  if not P.TryGetValue<string>('name', ToolName) then
    raise EMCPError.Create(ERR_INVALID_PARAMS, 'Missing tool name');

  Tool := FindTool(ToolName);

  if Tool = nil then
    raise EMCPError.Create(ERR_INVALID_PARAMS, 'Unknown tool: ' + ToolName);

  ArgsValue := P.GetValue('arguments');
  OwnsArgs := not (ArgsValue is TJSONObject);

  if OwnsArgs then
    Args := TJSONObject.Create
  else
    Args := TJSONObject(ArgsValue);

  try
    IsError := False;
    try
      Content := Tool.Handler(Args);
    except
      on E: Exception do
      begin
        IsError := True;
        Content := TJSONArray.Create;
        Content.Add(MCPText(E.Message));
      end;
    end;
  finally
    if OwnsArgs then
      Args.Free;
  end;

  if Content = nil then
    Content := TJSONArray.Create;

  Result := TJSONObject.Create;
  Result.AddPair('content', Content);
  Result.AddPair('isError', TJSONBool.Create(IsError));
end;

procedure TMCPServer.HandleMessage(const Line: string);
var
  Req: TJSONValue;
  Obj: TJSONObject;
  Method: string;
  Id, Params: TJSONValue;
  Res: TJSONObject;
begin
  Req := TJSONObject.ParseJSONValue(Line);

  if Req = nil then
  begin
    SendError(nil, ERR_PARSE, 'Parse error');
    Exit;
  end;

  try
    if not (Req is TJSONObject) then
    begin
      SendError(nil, ERR_INVALID_REQUEST, 'Invalid request');
      Exit;
    end;

    Obj := TJSONObject(Req);
    Id := Obj.GetValue('id');       // nil => notification
    Params := Obj.GetValue('params');

    if not Obj.TryGetValue<string>('method', Method) then
    begin
      // Responses from the client (no method) are ignored
      if Id <> nil then
        FTransport.Log('Ignoring message without method');
      Exit;
    end;

    // Notifications never get a response
    if (Id = nil) then
    begin
      FTransport.Log('Notification: ' + Method);
      Exit;
    end;

    try
      if Method = 'initialize' then
        Res := HandleInitialize(Params)
      else
      if Method = 'ping' then
        Res := TJSONObject.Create
      else
      if Method = 'tools/list' then
        Res := HandleToolsList
      else
      if Method = 'tools/call' then
        Res := HandleToolsCall(Params)
      else
        raise EMCPError.Create(ERR_METHOD_NOT_FOUND,
                               'Method not found: ' + Method);

      SendResult(Id, Res);
    except
      on E: EMCPError do
        SendError(Id, E.Code, E.Message);
      on E: Exception do
        SendError(Id, ERR_INTERNAL, E.Message);
    end;
  finally
    Req.Free;
  end;
end;

procedure TMCPServer.Run;
var
  Line: string;
begin
  while FTransport.ReadMessage(Line) do
  begin
    Line := Line.Trim;

    if Line = '' then
      Continue;

    try
      HandleMessage(Line);
    except
      on E: Exception do
        FTransport.Log('Unhandled error: ' + E.Message);
    end;
  end;
end;

end.
