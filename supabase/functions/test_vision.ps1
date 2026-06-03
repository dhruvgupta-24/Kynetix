# test_vision.ps1 — Direct OpenRouter vision diagnostic
# Tests google/gemini-2.5-flash with a 1x1 pixel JPEG base64 image
# to get the exact raw error from OpenRouter before any error wrapping

$OPENROUTER_KEY = "YOUR_OPENROUTER_KEY_HERE"
$MODEL = "google/gemini-2.5-flash"

# Minimal valid JPEG (1x1 white pixel) base64
$TINY_JPEG = "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVIP/2Q=="

Write-Host "=== OpenRouter Vision Test ===" -ForegroundColor Cyan
Write-Host "Model: $MODEL"
Write-Host "Endpoint: https://openrouter.ai/api/v1/chat/completions"
Write-Host ""

# Build request body - mirrors exactly what ai-chat-router sends
$body = @{
    model = $MODEL
    messages = @(
        @{
            role = "system"
            content = "You are a nutrition coach. Analyze food images."
        },
        @{
            role = "user"
            content = @(
                @{
                    type = "text"
                    text = "What food do you see in this image?"
                },
                @{
                    type = "image_url"
                    image_url = @{
                        url = "data:image/jpeg;base64,$TINY_JPEG"
                    }
                }
            )
        }
    )
    temperature = 0.25
    max_tokens = 2000
    stream = $true
} | ConvertTo-Json -Depth 10

Write-Host "Request body (truncated):"
Write-Host $body.Substring(0, [Math]::Min(500, $body.Length))
Write-Host ""
Write-Host "Sending request..."

try {
    $response = Invoke-WebRequest `
        -Uri "https://openrouter.ai/api/v1/chat/completions" `
        -Method POST `
        -ContentType "application/json" `
        -Headers @{
            "Authorization" = "Bearer $OPENROUTER_KEY"
            "HTTP-Referer" = "https://kynetix.app"
            "X-Title" = "Kynetix AI Coach"
        } `
        -Body $body `
        -ErrorAction Stop

    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    Write-Host "Status: $($response.StatusCode)"
    Write-Host "Content (first 500 chars):"
    Write-Host $response.Content.Substring(0, [Math]::Min(500, $response.Content.Length))
} catch {
    Write-Host "=== FAILURE ===" -ForegroundColor Red
    Write-Host "Status Code: $($_.Exception.Response.StatusCode.value__)"
    
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $errorBody = $reader.ReadToEnd()
        Write-Host "=== RAW ERROR BODY ===" -ForegroundColor Yellow
        Write-Host $errorBody
    } else {
        Write-Host "Exception: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "=== Now testing NON-STREAMING (stream=false) to get cleaner error ===" -ForegroundColor Cyan

$bodyNoStream = @{
    model = $MODEL
    messages = @(
        @{
            role = "system"
            content = "You are a nutrition coach. Analyze food images."
        },
        @{
            role = "user"
            content = @(
                @{
                    type = "text"
                    text = "What food do you see in this image?"
                },
                @{
                    type = "image_url"
                    image_url = @{
                        url = "data:image/jpeg;base64,$TINY_JPEG"
                    }
                }
            )
        }
    )
    temperature = 0.25
    max_tokens = 2000
    stream = $false
} | ConvertTo-Json -Depth 10

try {
    $response2 = Invoke-WebRequest `
        -Uri "https://openrouter.ai/api/v1/chat/completions" `
        -Method POST `
        -ContentType "application/json" `
        -Headers @{
            "Authorization" = "Bearer $OPENROUTER_KEY"
            "HTTP-Referer" = "https://kynetix.app"
            "X-Title" = "Kynetix AI Coach"
        } `
        -Body $bodyNoStream `
        -ErrorAction Stop

    Write-Host "=== SUCCESS (non-streaming) ===" -ForegroundColor Green
    Write-Host "Status: $($response2.StatusCode)"
    Write-Host "Full Response:"
    Write-Host $response2.Content
} catch {
    Write-Host "=== FAILURE (non-streaming) ===" -ForegroundColor Red
    Write-Host "Status Code: $($_.Exception.Response.StatusCode.value__)"
    
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $errorBody = $reader.ReadToEnd()
        Write-Host "=== RAW ERROR BODY ===" -ForegroundColor Yellow
        Write-Host $errorBody
    } else {
        Write-Host "Exception: $($_.Exception.Message)"
    }
}
