{***************************************************}
{  TeeChart MCP Server                              }
{  Copyright (c) 2026 by Steema Software            }
{***************************************************}
unit MCP.Transport;

{ Transport abstraction for the MCP server.
  Messages are single-line JSON strings (JSON-RPC 2.0).
  No VCL/FMX dependencies: compiles on Windows, Linux, macOS. }

interface

uses
  System.SysUtils, System.Classes;

type
  ITransport = interface
    ['{7B0E5B53-6C1C-4B0A-9A55-3E2F1D9C4A11}']
    /// Blocks until a message arrives. Returns False when the input is closed.
    function ReadMessage(out Msg: string): Boolean;
    procedure WriteMessage(const Msg: string);
    /// Diagnostics. Must NEVER go to the protocol output channel.
    procedure Log(const Msg: string);
  end;

  /// MCP "stdio" transport: one JSON message per line on stdin/stdout.
  TStdioTransport = class(TInterfacedObject, ITransport)
  private
    FUtf8: TEncoding;
    FInStream, FOutStream, FErrStream: THandleStream;
    FIn: TStreamReader;
    FOut, FErr: TStreamWriter;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadMessage(out Msg: string): Boolean;
    procedure WriteMessage(const Msg: string);
    procedure Log(const Msg: string);
  end;

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;
{$ENDIF}

{ TStdioTransport }

constructor TStdioTransport.Create;
begin
  inherited Create;

  FUtf8 := TUTF8Encoding.Create(False); // no BOM

  {$IFDEF MSWINDOWS}
  FInStream := THandleStream.Create(GetStdHandle(STD_INPUT_HANDLE));
  FOutStream := THandleStream.Create(GetStdHandle(STD_OUTPUT_HANDLE));
  FErrStream := THandleStream.Create(GetStdHandle(STD_ERROR_HANDLE));
  {$ELSE}
  FInStream := THandleStream.Create(0);
  FOutStream := THandleStream.Create(1);
  FErrStream := THandleStream.Create(2);
  {$ENDIF}

  FIn := TStreamReader.Create(FInStream, FUtf8, False);

  FOut := TStreamWriter.Create(FOutStream, FUtf8);
  FOut.NewLine := #10;
  FOut.AutoFlush := True;

  FErr := TStreamWriter.Create(FErrStream, FUtf8);
  FErr.NewLine := #10;
  FErr.AutoFlush := True;
end;

destructor TStdioTransport.Destroy;
begin
  FErr.Free;
  FOut.Free;
  FIn.Free;
  FErrStream.Free;
  FOutStream.Free;
  FInStream.Free;
  FUtf8.Free;
  inherited;
end;

function TStdioTransport.ReadMessage(out Msg: string): Boolean;
begin
  Msg := '';
  Result := not FIn.EndOfStream;
  if Result then
    Msg := FIn.ReadLine;
end;

procedure TStdioTransport.WriteMessage(const Msg: string);
begin
  FOut.WriteLine(Msg);
end;

procedure TStdioTransport.Log(const Msg: string);
begin
  FErr.WriteLine(Msg);
end;

end.
