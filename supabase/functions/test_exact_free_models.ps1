# test_exact_free_models.ps1 - Test actual free vision models found in API

$OPENROUTER_KEY = "YOUR_OPENROUTER_KEY_HERE"
$TINY_JPEG = "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVIP/2Q=="
$headers = @{ "Authorization" = "Bearer $OPENROUTER_KEY"; "HTTP-Referer" = "https://kynetix.app"; "X-Title" = "Kynetix" }

function Test-Vision($modelId) {
    Write-Host "--- $modelId ---" -ForegroundColor Yellow
    $body = @{
        model = $modelId
        messages = @(@{ role = "user"; content = @(
            @{ type = "text"; text = "What food? Say 'image ok' if received." }
            @{ type = "image_url"; image_url = @{ url = "data:image/jpeg;base64,$TINY_JPEG" } }
        )})
        max_tokens = 100
        stream = $false
    } | ConvertTo-Json -Depth 10
    try {
        $r = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" -Method POST -ContentType "application/json" -Headers $headers -Body $body -TimeoutSec 30 -ErrorAction Stop
        $content = ($r.Content | ConvertFrom-Json).choices[0].message.content
        Write-Host "  SUCCESS: $content" -ForegroundColor Green
        return $true
    } catch {
        if ($_.Exception.Response) { $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host "  FAIL ($($_.Exception.Response.StatusCode.value__)): $($reader.ReadToEnd().Substring(0,200))" -ForegroundColor Red } else { Write-Host "  ERR: $($_.Exception.Message)" -ForegroundColor Red }
        return $false
    }
}

# Free vision models identified from API
Test-Vision "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"
# Ultra-cheap vision models
Test-Vision "perceptron/perceptron-mk1"
Test-Vision "qwen/qwen3.6-flash"
Test-Vision "qwen/qwen3.6-35b-a3b"
