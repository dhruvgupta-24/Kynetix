# test_vision2.ps1 — Compare text vs vision token costs on OpenRouter

$OPENROUTER_KEY = "YOUR_OPENROUTER_KEY_HERE"
$TINY_JPEG = "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVIP/2Q=="

Write-Host "=== Test 1: Vision model (gemini-2.5-flash) with max_tokens=300 ===" -ForegroundColor Cyan
$body1 = @{
    model = "google/gemini-2.5-flash"
    messages = @(
        @{ role = "system"; content = "You are a nutrition coach." },
        @{
            role = "user"
            content = @(
                @{ type = "text"; text = "What food do you see?" },
                @{ type = "image_url"; image_url = @{ url = "data:image/jpeg;base64,$TINY_JPEG" } }
            )
        }
    )
    temperature = 0.25
    max_tokens = 300
    stream = $false
} | ConvertTo-Json -Depth 10

try {
    $r1 = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" -Method POST -ContentType "application/json" -Headers @{ "Authorization" = "Bearer $OPENROUTER_KEY"; "HTTP-Referer" = "https://kynetix.app"; "X-Title" = "Kynetix AI Coach" } -Body $body1 -ErrorAction Stop
    Write-Host "SUCCESS: $($r1.Content.Substring(0, 300))" -ForegroundColor Green
} catch {
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    Write-Host "FAIL ($($_.Exception.Response.StatusCode.value__)): $($reader.ReadToEnd())" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Test 2: Text model (deepseek-chat-v3-0324) with max_tokens=1500 ===" -ForegroundColor Cyan
$body2 = @{
    model = "deepseek/deepseek-chat-v3-0324"
    messages = @(
        @{ role = "system"; content = "You are a nutrition coach." },
        @{ role = "user"; content = "What is a healthy breakfast?" }
    )
    temperature = 0.25
    max_tokens = 1500
    stream = $false
} | ConvertTo-Json -Depth 10

try {
    $r2 = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" -Method POST -ContentType "application/json" -Headers @{ "Authorization" = "Bearer $OPENROUTER_KEY"; "HTTP-Referer" = "https://kynetix.app"; "X-Title" = "Kynetix AI Coach" } -Body $body2 -ErrorAction Stop
    Write-Host "SUCCESS: $($r2.Content.Substring(0, 300))" -ForegroundColor Green
} catch {
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    Write-Host "FAIL ($($_.Exception.Response.StatusCode.value__)): $($reader.ReadToEnd())" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Test 3: Check OpenRouter balance/credits ===" -ForegroundColor Cyan
try {
    $credits = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/auth/key" -Method GET -Headers @{ "Authorization" = "Bearer $OPENROUTER_KEY" } -ErrorAction Stop
    Write-Host "Credits info: $($credits.Content)" -ForegroundColor Green
} catch {
    Write-Host "Could not check credits: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Test 4: Free vision model (google/gemini-2.5-flash:free) with max_tokens=300 ===" -ForegroundColor Cyan
$body4 = @{
    model = "google/gemini-2.5-flash:free"
    messages = @(
        @{ role = "system"; content = "You are a nutrition coach." },
        @{
            role = "user"
            content = @(
                @{ type = "text"; text = "What food do you see?" },
                @{ type = "image_url"; image_url = @{ url = "data:image/jpeg;base64,$TINY_JPEG" } }
            )
        }
    )
    temperature = 0.25
    max_tokens = 300
    stream = $false
} | ConvertTo-Json -Depth 10

try {
    $r4 = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" -Method POST -ContentType "application/json" -Headers @{ "Authorization" = "Bearer $OPENROUTER_KEY"; "HTTP-Referer" = "https://kynetix.app"; "X-Title" = "Kynetix AI Coach" } -Body $body4 -ErrorAction Stop
    Write-Host "SUCCESS: $($r4.Content.Substring(0, 500))" -ForegroundColor Green
} catch {
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    Write-Host "FAIL ($($_.Exception.Response.StatusCode.value__)): $($reader.ReadToEnd())" -ForegroundColor Red
}
