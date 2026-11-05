# Test HTTP MCP server endpoints
param(
    [int]$Port = 8089
)

$exePath = Join-Path $PSScriptRoot "..\bin\TeeChart_MCP.exe"
if (-not (Test-Path $exePath)) {
    Write-Error "Executable not found at $exePath"
    exit 1
}

Write-Host "Starting TeeChart_MCP HTTP server on port $Port..."
$p = Start-Process -FilePath $exePath -ArgumentList "--http $Port" -PassThru
Start-Sleep -Seconds 1

try {
    $baseUrl = "http://127.0.0.1:$Port/mcp"

    # 1. CORS Preflight
    Write-Host "[1/5] Testing OPTIONS (CORS preflight)..."
    $opt = Invoke-WebRequest -Uri $baseUrl -Method OPTIONS -UseBasicParsing
    Write-Host "      Status: $($opt.StatusCode), CORS Origin: $($opt.Headers['Access-Control-Allow-Origin'])"

    # 2. Initialize
    Write-Host "[2/5] Testing POST initialize..."
    $initBody = '{"jsonrpc": "2.0", "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "test", "version": "1.0"}}, "id": 1}'
    $init = Invoke-RestMethod -Uri $baseUrl -Method POST -Body $initBody -ContentType "application/json"
    Write-Host "      Server: $($init.result.serverInfo.name) v$($init.result.serverInfo.version)"

    # 3. Tools list
    Write-Host "[3/5] Testing POST tools/list..."
    $list = Invoke-RestMethod -Uri $baseUrl -Method POST -Body '{"jsonrpc": "2.0", "method": "tools/list", "id": 2}' -ContentType "application/json"
    Write-Host "      Tools found: $($list.result.tools.Count)"

    # 4. Echo tool call
    Write-Host "[4/5] Testing POST tools/call (echo)..."
    $echoBody = '{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "echo", "arguments": {"text": "TeeChart MCP HTTP test"}}, "id": 3}'
    $echo = Invoke-RestMethod -Uri $baseUrl -Method POST -Body $echoBody -ContentType "application/json"
    Write-Host "      Echo result: $($echo.result.content[0].text)"

    # 5. Streamable HTTP SSE response
    Write-Host "[5/5] Testing Streamable HTTP (Accept: text/event-stream)..."
    $sse = Invoke-WebRequest -Uri $baseUrl -Method POST -Body $echoBody -Headers @{ "Accept" = "text/event-stream" } -ContentType "application/json" -UseBasicParsing
    Write-Host "      Content-Type: $($sse.Headers['Content-Type'])"
    Write-Host "      Body: $($sse.Content.Trim())"

    Write-Host "`nAll HTTP tests completed successfully!"
}
finally {
    Stop-Process -Id $p.Id -Force
}

