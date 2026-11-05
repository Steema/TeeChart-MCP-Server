# TeeChart-MCP-Server

MCP Server to create charts and plots using the TeeChart library

<img width="1802" height="1482" alt="image" src="https://github.com/user-attachments/assets/c828cac8-e075-44a0-81ae-3c6dc1262ff0" />

# Running as Stdio Server (Default)

Move first to the `bin` subfolder where the executable `TeeChart_MCP.exe` resides.

```powershell
$requests = @(
    '{"jsonrpc": "2.0", "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "test", "version": "1.0"}}, "id": 1}',
    '{"jsonrpc": "2.0", "method": "tools/list", "id": 2}'
)
$requests | .\teechart_mcp.exe
```

Installing the MCP server in the different IDEs usually consists of adding it as a simple STDIO local path, for example in Claude, ChatGPT Codex, Antigravity, Cursor, Kai etc.

For example in Antigravity you should add it manually at the configuration file:

`C:\Users\Your_Name\.gemini\config\mcp_config.json`

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

# Hosting as an HTTP Server

The server can also be hosted over HTTP instead of running as a local stdio process. It supports both **Streamable HTTP** (MCP spec 2025-03-26) and **HTTP+SSE** (MCP spec 2024-11-05) on the `/mcp` endpoint, complete with CORS headers.

### Starting the HTTP server:

```powershell
# Start on default port 8080
.\teechart_mcp.exe --http

# Or specify a custom port
.\teechart_mcp.exe --http 8089
```

The MCP endpoint will be available at:
```
http://localhost:8080/mcp
```

### Command-line options:

| Option | Description |
|---|---|
| `(none)` | Runs as stdio MCP server (default) |
| `--http [port]` | Runs as HTTP MCP server (default port: 8080) |
| `-p, --port <port>` | Sets the HTTP port |
| `-h, --help` | Shows usage and options |

### Configuring in MCP Clients (Remote / HTTP):

For MCP clients that support remote HTTP/SSE servers:

```json
{
  "mcpServers": {
    "teechart-mcp": {
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

### Testing HTTP endpoints with PowerShell:

```powershell
# Initialize
$init = '{"jsonrpc": "2.0", "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "test", "version": "1.0"}}, "id": 1}'
Invoke-RestMethod -Uri "http://localhost:8080/mcp" -Method POST -Body $init -ContentType "application/json"

# List available tools
$tools = '{"jsonrpc": "2.0", "method": "tools/list", "id": 2}'
Invoke-RestMethod -Uri "http://localhost:8080/mcp" -Method POST -Body $tools -ContentType "application/json"
```

## Using it

Once installed you can simple request to create charts using TeeChart, and getting the output as a PNG, JPEG, SVG image etc.

```
Use TeeChart to create a line chart with values 3, 7, 4 i 9; set the title “TeeChart Test” and export it as a PNG
```

# Testing in Ubuntu Linux with OpenCode

<img width="1594" height="1078" alt="image" src="https://github.com/user-attachments/assets/b43f9191-5097-4fb4-81d7-91101cdfb768" />

Using the [opencode.ai](https://opencode.ai/) AI agent, first ask opencode to install the MCP server (the binary under the [bin folder](https://github.com/Steema/TeeChart-MCP-Server/tree/main/bin) here in this repo).

Then ask it to use the TeeChart mcp server to generate a chart with your data.
