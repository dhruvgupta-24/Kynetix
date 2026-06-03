# test_vision3.ps1 — Verify free vision model works

$OPENROUTER_KEY = "YOUR_OPENROUTER_KEY_HERE"
$TINY_JPEG = "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVIP/2Q=="

Write-Host "=== Test: google/gemini-2.5-flash:free with vision (non-streaming) ===" -ForegroundColor Cyan
$body = @{
    model = "google/gemini-2.5-flash:free"
    messages = @(
        @{ role = "system"; content = "You are a nutrition coach." },
        @{
            role = "user"
            content = @(
                @{ type = "text"; text = "What food do you see in this image?" },
                @{ type = "image_url"; image_url = @{ url = "data:image/jpeg;base64,$TINY_JPEG" } }
            )
        }
    )
    temperature = 0.25
    max_tokens = 1500
    stream = $false
} | ConvertTo-Json -Depth 10

try {
    $r = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" -Method POST -ContentType "application/json" -Headers @{ "Authorization" = "Bearer $OPENROUTER_KEY"; "HTTP-Referer" = "https://kynetix.app"; "X-Title" = "Kynetix AI Coach" } -Body $body -ErrorAction Stop
    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    Write-Host "Status: $($r.StatusCode)"
    Write-Host "Response: $($r.Content.Substring(0, [Math]::Min(800, $r.Content.Length)))"
} catch {
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $errorBody = $reader.ReadToEnd()
        Write-Host "=== FAIL ($($_.Exception.Response.StatusCode.value__)) ===" -ForegroundColor Red
        Write-Host $errorBody
    } else {
        Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Test: google/gemini-2.5-flash:free streaming ===" -ForegroundColor Cyan
$bodyStream = @{
    model = "google/gemini-2.5-flash:free"
    messages = @(
        @{ role = "system"; content = "You are a nutrition coach." },
        @{
            role = "user"
            content = @(
                @{ type = "text"; text = "What food do you see in this image?" },
                @{ type = "image_url"; image_url = @{ url = "data:image/jpeg;base64,$TINY_JPEG" } }
            )
        }
    )
    temperature = 0.25
    max_tokens = 1500
    stream = $true
} | ConvertTo-Json -Depth 10

try {
    $r2 = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" -Method POST -ContentType "application/json" -Headers @{ "Authorization" = "Bearer $OPENROUTER_KEY"; "HTTP-Referer" = "https://kynetix.app"; "X-Title" = "Kynetix AI Coach" } -Body $bodyStream -ErrorAction Stop
    Write-Host "=== SUCCESS (streaming) ===" -ForegroundColor Green
    Write-Host "Status: $($r2.StatusCode)"
    Write-Host "First 500 chars of stream: $($r2.Content.Substring(0, [Math]::Min(500, $r2.Content.Length)))"
} catch {
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $errorBody = $reader.ReadToEnd()
        Write-Host "=== FAIL streaming ($($_.Exception.Response.StatusCode.value__)) ===" -ForegroundColor Red
        Write-Host $errorBody
    } else {
        Write-Host "Streaming exception: $($_.Exception.Message)" -ForegroundColor Red
    }
}
