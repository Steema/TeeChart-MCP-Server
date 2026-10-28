# TeeChart-MCP-Server

MCP Server to create charts and plots using the TeeChart library

## Testing in Windows with Powershell:

Move first to the bin subfolder where the executable TeeChart_MCP.exe resides.

```powershell
$requests = @(
    '{"jsonrpc": "2.0", "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "test", "version": "1.0"}}, "id": 1}',
    '{"jsonrpc": "2.0", "method": "tools/list", "id": 2}'
)
$requests | .\teechart_mcp.exe
```

Installing the MCP server in the different ides usually consists of adding it as a simple STDIO local path, for example in Claude, ChatGPT Codex, Antigravity etc.

Ask the AI itself how to install and use the MCP server.

For example in Antigravity you should add it manually at the configuration file:

C:\Users\Your_Name\.gemini\config\mcp_config.json

```json
{
  "mcpServers": {
    "teechart-mcp": {
      "command": "C:/github/teechart_mcp/bin/teechart_mcp.exe",
      "args": [],
      "env": {}
    }
  }
}
```



## Using it

Once installed you can simple request to create charts using TeeChart, and getting the output as a PNG, JPEG, SVG image etc.

```
Use TeeChart to create a line chart with values 3, 7, 4 i 9; set the title “TeeChart Test” and export it as a PNG
```
