# test_models.ps1 - Find free vision models on OpenRouter

$OPENROUTER_KEY = "YOUR_OPENROUTER_KEY_HERE"

Write-Host "=== Account Credits ===" -ForegroundColor Cyan
try {
    $credits = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/auth/key" -Method GET -Headers @{ "Authorization" = "Bearer $OPENROUTER_KEY" } -ErrorAction Stop
    Write-Host $credits.Content
} catch {
    Write-Host "Credits check failed: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "=== Free Vision Models ===" -ForegroundColor Cyan
try {
    $models = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/models" -Method GET -ErrorAction Stop
    $json = $models.Content | ConvertFrom-Json
    $freeVision = $json.data | Where-Object {
        $_.pricing.prompt -eq "0" -and
        ($_.architecture.input_modalities -contains "image" -or $_.id -like "*vision*" -or $_.id -like "*gemini*" -or $_.id -like "*llava*")
    }
    Write-Host "Found $($freeVision.Count) free vision candidates:"
    foreach ($m in $freeVision) {
        Write-Host "  - $($m.id) | price=$($m.pricing.prompt) | modalities=$($m.architecture.input_modalities -join ',')"
    }
} catch {
    Write-Host "Models list failed: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "=== Test meta-llama/llama-4-scout:free (free, vision) ===" -ForegroundColor Cyan
$TINY_JPEG = "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVIP/2Q=="

$body = @{
    model = "meta-llama/llama-4-scout:free"
    messages = @(
        @{ role = "system"; content = "You are a nutrition coach." },
        @{
            role = "user"
            content = @(
                @{ type = "text"; text = "What food do you see in this image?" }
                @{ type = "image_url"; image_url = @{ url = "data:image/jpeg;base64,$TINY_JPEG" } }
            )
        }
    )
    temperature = 0.25
    max_tokens = 1500
    stream = $false
} | ConvertTo-Json -Depth 10

try {
    $r = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" -Method POST -ContentType "application/json" -Headers @{ "Authorization" = "Bearer $OPENROUTER_KEY"; "HTTP-Referer" = "https://kynetix.app"; "X-Title" = "Kynetix" } -Body $body -ErrorAction Stop
    Write-Host "SUCCESS: $($r.Content.Substring(0, 300))" -ForegroundColor Green
} catch {
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        Write-Host "FAIL ($($_.Exception.Response.StatusCode.value__)): $($reader.ReadToEnd())" -ForegroundColor Red
    } else {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Test google/gemini-2.0-flash-exp:free ===" -ForegroundColor Cyan
$body2 = $body | ConvertFrom-Json
$body2.model = "google/gemini-2.0-flash-exp:free"
$body2json = $body2 | ConvertTo-Json -Depth 10

try {
    $r2 = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" -Method POST -ContentType "application/json" -Headers @{ "Authorization" = "Bearer $OPENROUTER_KEY"; "HTTP-Referer" = "https://kynetix.app"; "X-Title" = "Kynetix" } -Body $body2json -ErrorAction Stop
    Write-Host "SUCCESS: $($r2.Content.Substring(0, 300))" -ForegroundColor Green
} catch {
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        Write-Host "FAIL ($($_.Exception.Response.StatusCode.value__)): $($reader.ReadToEnd())" -ForegroundColor Red
    } else {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}
