# Test script to generate a sample Pie Chart via TeeChart HTTP MCP Server
param(
    [string]$HostName = "127.0.0.1",
    [int]$Port = 8080,
    [string]$OutputPath = "$PSScriptRoot\sample_pie_chart.png"
)

$url = "http://${HostName}:${Port}/mcp"

Write-Host "Target MCP endpoint: $url" -ForegroundColor Cyan

# 1. Initialize session
Write-Host "`n[1/4] Initializing connection..." -ForegroundColor Yellow
$initBody = @{
    jsonrpc = "2.0"
    method = "initialize"
    params = @{
        protocolVersion = "2024-11-05"
        capabilities = @{}
        clientInfo = @{ name = "pie-chart-tester"; version = "1.0" }
    }
    id = 1
} | ConvertTo-Json -Depth 5 -Compress

$init = Invoke-RestMethod -Uri $url -Method POST -ContentType "application/json" -Body $initBody
Write-Host "      Connected to: $($init.result.serverInfo.name) v$($init.result.serverInfo.version)" -ForegroundColor Green

# 2. Create Chart
Write-Host "`n[2/4] Creating 3D chart canvas..." -ForegroundColor Yellow
$createBody = @{
    jsonrpc = "2.0"
    method = "tools/call"
    params = @{
        name = "create_chart"
        arguments = @{
            width = 800
            height = 500
            title = "Revenue by Division 2026"
            view3d = $true
        }
    }
    id = 2
} | ConvertTo-Json -Depth 5 -Compress

$createResp = Invoke-RestMethod -Uri $url -Method POST -ContentType "application/json" -Body $createBody
$chartId = [regex]::Match($createResp.result.content[0].text, 'chart\d+').Value
if (-not $chartId) {
    Write-Error "Failed to obtain chart ID: $($createResp.result.content[0].text)"
    exit 1
}
Write-Host "      Chart created with ID: $chartId" -ForegroundColor Green

# 3. Add Pie Series
Write-Host "`n[3/4] Adding Pie series data..." -ForegroundColor Yellow
$seriesBody = @{
    jsonrpc = "2.0"
    method = "tools/call"
    params = @{
        name = "add_series"
        arguments = @{
            chart_id = $chartId
            type = "pie"
            title = "Divisions"
            values = @(42.5, 28.0, 17.5, 12.0)
            labels = @("Cloud Services", "Hardware", "Consulting", "Support")
        }
    }
    id = 3
} | ConvertTo-Json -Depth 5 -Compress

$seriesResp = Invoke-RestMethod -Uri $url -Method POST -ContentType "application/json" -Body $seriesBody
Write-Host "      $($seriesResp.result.content[0].text)" -ForegroundColor Green

# 4. Export Chart to PNG
Write-Host "`n[4/4] Exporting chart to $OutputPath..." -ForegroundColor Yellow
$resolvedPath = [System.IO.Path]::GetFullPath($OutputPath)
$exportBody = @{
    jsonrpc = "2.0"
    method = "tools/call"
    params = @{
        name = "export_chart"
        arguments = @{
            chart_id = $chartId
            format = "png"
            path = $resolvedPath
        }
    }
    id = 4
} | ConvertTo-Json -Depth 5 -Compress

$exportResp = Invoke-RestMethod -Uri $url -Method POST -ContentType "application/json" -Body $exportBody
Write-Host "      $($exportResp.result.content[0].text)" -ForegroundColor Green

if (Test-Path $resolvedPath) {
    $bytes = (Get-Item $resolvedPath).Length
    Write-Host "`nSuccess! Pie chart exported to: $resolvedPath ($bytes bytes)" -ForegroundColor Cyan
} else {
    Write-Error "File was not found after export."
}

