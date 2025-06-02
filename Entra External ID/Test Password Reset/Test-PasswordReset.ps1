# External ID Password Reset Testing Script - v1.0 API
# Correct URL format for External ID

# External ID Password Reset Testing Script - Enhanced with Configuration
# Based on Microsoft native authentication best practices

# Configuration object (based on mobile app JSON pattern)
$config = @{
    client_id = "ce65863c-6ed6-41c3-b16c-d9df898714f3"
    tenant_subdomain = "thewolfecustomers"
    authorities = @(
        @{
            authority_url = "https://thewolfecustomers.ciamlogin.com/thewolfecustomers.onmicrosoft.com/"
        }
    )
    challenge_types = @("oob", "redirect")  # Required for SSPR flow per Microsoft docs
}

# Prompt for user email
$userEmail = Read-Host "Enter the email address for password reset"

# Derived URLs from configuration
$baseUrl = $config.authorities[0].authority_url.TrimEnd('/')
$challengeTypesString = $config.challenge_types -join " "  # Space-separated as per API docs

# Helper function to display request/response details
function Show-RequestDetails {
    param(
        [string]$StepName,
        [string]$Url,
        [hashtable]$Body,
        [object]$Response = $null,
        [string]$ErrorMessage = $null,
        [object]$ErrorResponse = $null
    )
    
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor DarkGray
    Write-Host " $StepName" -ForegroundColor Magenta
    Write-Host "===========================================" -ForegroundColor DarkGray
    
    Write-Host ""
    Write-Host "URL:" -ForegroundColor Cyan
    Write-Host "  $Url" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "Request Body:" -ForegroundColor Yellow
    foreach ($key in $Body.Keys) {
        if ($key -eq "new_password") {
            Write-Host "  $key = [HIDDEN]" -ForegroundColor Gray
        } elseif ($key -eq "continuation_token" -and $Body[$key].Length -gt 50) {
            # Truncate long continuation tokens for readability
            $truncatedToken = $Body[$key].Substring(0, 50) + "..."
            Write-Host "  $key = $truncatedToken" -ForegroundColor Gray
        } else {
            Write-Host "  $key = $($Body[$key])" -ForegroundColor Gray
        }
    }
    
    if ($Response) {
        Write-Host ""
        Write-Host "Response:" -ForegroundColor Green
        if ($Response.continuation_token) {
            # Truncate continuation token for display
            $token = $Response.continuation_token
            if ($token.Length -gt 50) { 
                $displayToken = $token.Substring(0, 50) + "..."
            } else {
                $displayToken = $token
            }
            Write-Host "  continuation_token = $displayToken" -ForegroundColor Gray
        }
        if ($Response.access_token) {
            Write-Host "  access_token = [RECEIVED]" -ForegroundColor Gray
        }
        # Show any other response properties
        $Response.PSObject.Properties | Where-Object { $_.Name -notin @('continuation_token', 'access_token') } | ForEach-Object {
            Write-Host "  $($_.Name) = $($_.Value)" -ForegroundColor Gray
        }
    }
    
    if ($ErrorMessage -or $ErrorResponse) {
        Write-Host ""
        Write-Host "Error Details:" -ForegroundColor Red
        if ($ErrorMessage) {
            Write-Host "  Summary: $ErrorMessage" -ForegroundColor Gray
        }
        
        if ($ErrorResponse) {
            Write-Host ""
            Write-Host "  HTTP Error Response:" -ForegroundColor Red
            if ($ErrorResponse.error) {
                Write-Host "    error: $($ErrorResponse.error)" -ForegroundColor Gray
            }
            if ($ErrorResponse.error_description) {
                Write-Host "    error_description:" -ForegroundColor Gray
                # Split long descriptions into multiple lines with proper indentation
                $desc = $ErrorResponse.error_description
                $maxLength = 80
                if ($desc.Length -gt $maxLength) {
                    $words = $desc -split ' '
                    $currentLine = ""
                    foreach ($word in $words) {
                        if (($currentLine + $word).Length -gt $maxLength) {
                            Write-Host "      $currentLine" -ForegroundColor Gray
                            $currentLine = $word + " "
                        } else {
                            $currentLine += $word + " "
                        }
                    }
                    if ($currentLine.Trim()) {
                        Write-Host "      $($currentLine.Trim())" -ForegroundColor Gray
                    }
                } else {
                    Write-Host "      $desc" -ForegroundColor Gray
                }
            }
            if ($ErrorResponse.error_codes) {
                Write-Host "    error_codes: $($ErrorResponse.error_codes -join ', ')" -ForegroundColor Gray
            }
            if ($ErrorResponse.trace_id) {
                Write-Host "    trace_id: $($ErrorResponse.trace_id)" -ForegroundColor Gray
            }
            if ($ErrorResponse.correlation_id) {
                Write-Host "    correlation_id: $($ErrorResponse.correlation_id)" -ForegroundColor Gray
            }
        }
    }
    
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor DarkGray
}

# Helper function to extract detailed error information
function Get-DetailedErrorInfo {
    param([object]$Exception)
    
    $errorDetails = @{
        StatusCode = $null
        ReasonPhrase = $null
        ErrorBody = $null
        Summary = $null
    }
    
    try {
        # Get status code and reason phrase
        if ($Exception.Exception.Response) {
            $errorDetails.StatusCode = $Exception.Exception.Response.StatusCode.value__
            $errorDetails.ReasonPhrase = $Exception.Exception.Response.ReasonPhrase
        }
        
        # Try to get the error response body using different methods
        $errorBody = $null
        
        # Method 1: Check if there's an error record with response content
        if ($Exception.ErrorDetails -and $Exception.ErrorDetails.Message) {
            $errorBody = $Exception.ErrorDetails.Message
        }
        # Method 2: Try to read from the response stream (if available)
        elseif ($Exception.Exception.Response -and $Exception.Exception.Response.Content) {
            try {
                $stream = $Exception.Exception.Response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $reader = New-Object System.IO.StreamReader($stream)
                $errorBody = $reader.ReadToEnd()
                $reader.Close()
                $stream.Close()
            } catch {
                # Stream reading failed, continue without error body
            }
        }
        
        # Try to parse the error body as JSON
        if ($errorBody) {
            try {
                $errorDetails.ErrorBody = $errorBody | ConvertFrom-Json
            } catch {
                # Not valid JSON, store as raw text
                $errorDetails.ErrorBody = @{ 
                    raw_response = $errorBody
                    parse_error = "Could not parse as JSON"
                }
            }
        }
        
        # Create summary
        if ($errorDetails.StatusCode) {
            $errorDetails.Summary = "HTTP $($errorDetails.StatusCode) - $($errorDetails.ReasonPhrase)"
        } else {
            $errorDetails.Summary = $Exception.Exception.Message
        }
        
    } catch {
        $errorDetails.Summary = $Exception.Exception.Message
    }
    
    return $errorDetails
}

# Alternative approach using Invoke-WebRequest for better error handling
function Invoke-ApiRequest {
    param(
        [string]$Uri,
        [hashtable]$Body,
        [hashtable]$Headers
    )
    
    try {
        # Use Invoke-WebRequest instead of Invoke-RestMethod for better error handling
        $response = Invoke-WebRequest -Uri $Uri -Method POST -Headers $Headers -Body $Body -ErrorAction Stop
        
        # Parse the JSON response
        $jsonResponse = $response.Content | ConvertFrom-Json
        return @{
            Success = $true
            Data = $jsonResponse
            StatusCode = $response.StatusCode
        }
        
    } catch {
        $errorInfo = @{
            Success = $false
            StatusCode = $null
            ErrorBody = $null
            Exception = $_
        }
        
        # Extract status code
        if ($_.Exception.Response) {
            $errorInfo.StatusCode = $_.Exception.Response.StatusCode.value__
        }
        
        # Extract error response body
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            try {
                $errorInfo.ErrorBody = $_.ErrorDetails.Message | ConvertFrom-Json
            } catch {
                $errorInfo.ErrorBody = @{ raw_response = $_.ErrorDetails.Message }
            }
        }
        
        return $errorInfo
    }
}

# Headers for all requests
$headers = @{
    "Content-Type" = "application/x-www-form-urlencoded"
}

Write-Host "========================================" -ForegroundColor Green
Write-Host " External ID Password Reset Flow Test" -ForegroundColor Green  
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Authority: $($config.authorities[0].authority_url)" -ForegroundColor Gray
Write-Host "  Client ID: $($config.client_id)" -ForegroundColor Gray
Write-Host "  Challenge Types: $challengeTypesString" -ForegroundColor Gray
Write-Host "  User Email: $userEmail" -ForegroundColor Gray
Write-Host ""

# Step 1: Start - Request password reset
Write-Host ""
Write-Host "Step 1: Starting password reset flow..." -ForegroundColor Cyan

$startBody = @{
    "client_id" = $config.client_id
    "challenge_type" = $challengeTypesString  # Space-separated: "oob redirect"
    "username" = $userEmail
}

$startUrl = "$baseUrl/resetpassword/v1.0/start"

try {
    # Use the new API request function for better error handling
    $result = Invoke-ApiRequest -Uri $startUrl -Body $startBody -Headers $headers
    
    if ($result.Success) {
        Show-RequestDetails -StepName "STEP 1: START" -Url $startUrl -Body $startBody -Response $result.Data
        
        Write-Host "SUCCESS: Password reset flow started!" -ForegroundColor Green
        
        # Store the continuation token for next step
        $continuationToken = $result.Data.continuation_token
    } else {
        $errorSummary = "HTTP $($result.StatusCode) - Request failed"
        Show-RequestDetails -StepName "STEP 1: START (FAILED)" -Url $startUrl -Body $startBody -ErrorMessage $errorSummary -ErrorResponse $result.ErrorBody
        
        Write-Host "FAILED: Start request failed" -ForegroundColor Red
        
        # Additional troubleshooting info
        if ($result.StatusCode -eq 404) {
            Write-Host ""
            Write-Host "Troubleshooting 404 error:" -ForegroundColor Yellow
            Write-Host "1. Verify Native Authentication is enabled in your External ID tenant" -ForegroundColor Gray
            Write-Host "2. Check that the user exists in your tenant" -ForegroundColor Gray
            Write-Host "3. Ensure your app registration supports public client flows" -ForegroundColor Gray
        } elseif ($result.StatusCode -eq 400) {
            Write-Host ""
            Write-Host "Troubleshooting 400 error:" -ForegroundColor Yellow
            Write-Host "1. Check client_id is correct" -ForegroundColor Gray
            Write-Host "2. Verify challenge_type parameter" -ForegroundColor Gray
            Write-Host "3. Ensure username format is correct" -ForegroundColor Gray
        }
        exit 1
    }
    
} catch {
    Write-Host "ERROR: Unexpected error in Step 1" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Step 2: Challenge - Trigger OTP email
Write-Host ""
Write-Host "Step 2: Requesting OTP email..." -ForegroundColor Cyan

$challengeBody = @{
    "client_id" = $config.client_id
    "continuation_token" = $continuationToken
}

$challengeUrl = "$baseUrl/resetpassword/v1.0/challenge"

try {
    $challengeResponse = Invoke-RestMethod -Uri $challengeUrl -Method POST -Headers $headers -Body $challengeBody -ErrorAction Stop
    
    Show-RequestDetails -StepName "STEP 2: CHALLENGE" -Url $challengeUrl -Body $challengeBody -Response $challengeResponse
    
    Write-Host "SUCCESS: OTP email sent successfully!" -ForegroundColor Green
    
    # Update continuation token
    $continuationToken = $challengeResponse.continuation_token
    
    Write-Host ""
    Write-Host "Check your email for the OTP code, then continue to Step 3" -ForegroundColor Magenta
    
} catch {
    $errorInfo = Get-DetailedErrorInfo -Exception $_
    
    Show-RequestDetails -StepName "STEP 2: CHALLENGE (FAILED)" -Url $challengeUrl -Body $challengeBody -ErrorMessage $errorInfo.Summary -ErrorResponse $errorInfo.ErrorBody
    
    Write-Host "FAILED: Challenge request failed" -ForegroundColor Red
    exit 1
}

# Pause for user to get OTP
Write-Host ""
$otp = Read-Host "Enter the OTP code from your email"

# Step 3: Continue - Submit OTP
Write-Host ""
Write-Host "Step 3: Submitting OTP..." -ForegroundColor Cyan

$continueBody = @{
    "client_id" = $config.client_id
    "continuation_token" = $continuationToken
    "grant_type" = "oob"
    "oob" = $otp
}

$continueUrl = "$baseUrl/resetpassword/v1.0/continue"

try {
    $continueResponse = Invoke-RestMethod -Uri $continueUrl -Method POST -Headers $headers -Body $continueBody -ErrorAction Stop
    
    Show-RequestDetails -StepName "STEP 3: CONTINUE" -Url $continueUrl -Body $continueBody -Response $continueResponse
    
    Write-Host "SUCCESS: OTP verification successful!" -ForegroundColor Green
    
    # Update continuation token
    $continuationToken = $continueResponse.continuation_token
    
} catch {
    $errorInfo = Get-DetailedErrorInfo -Exception $_
    
    Show-RequestDetails -StepName "STEP 3: CONTINUE (FAILED)" -Url $continueUrl -Body $continueBody -ErrorMessage $errorInfo.Summary -ErrorResponse $errorInfo.ErrorBody
    
    Write-Host "FAILED: OTP verification failed" -ForegroundColor Red
    
    if ($errorInfo.StatusCode -eq 400) {
        Write-Host "The OTP might be incorrect or expired. Try again." -ForegroundColor Yellow
    }
    exit 1
}

# Step 4: Submit - Set new password
Write-Host ""
Write-Host "Step 4: Setting new password..." -ForegroundColor Cyan

$newPassword = Read-Host "Enter new password" -AsSecureString
$newPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($newPassword))

$submitBody = @{
    "client_id" = $config.client_id
    "continuation_token" = $continuationToken
    "new_password" = $newPasswordPlain
}

$submitUrl = "$baseUrl/resetpassword/v1.0/submit"

try {
    $submitResponse = Invoke-RestMethod -Uri $submitUrl -Method POST -Headers $headers -Body $submitBody -ErrorAction Stop
    
    Show-RequestDetails -StepName "STEP 4: SUBMIT" -Url $submitUrl -Body $submitBody -Response $submitResponse
    
    Write-Host "SUCCESS: Password reset completed successfully!" -ForegroundColor Green
    Write-Host "User can now sign in with the new password." -ForegroundColor Green
    
    # Display any additional response info
    if ($submitResponse.access_token) {
        Write-Host "Access token received (user is now authenticated)" -ForegroundColor Green
    }
    
} catch {
    $errorInfo = Get-DetailedErrorInfo -Exception $_
    
    Show-RequestDetails -StepName "STEP 4: SUBMIT (FAILED)" -Url $submitUrl -Body $submitBody -ErrorMessage $errorInfo.Summary -ErrorResponse $errorInfo.ErrorBody
    
    Write-Host "FAILED: Password reset failed" -ForegroundColor Red
    
    if ($errorInfo.StatusCode -eq 400) {
        Write-Host "Check password complexity requirements" -ForegroundColor Yellow
    }
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Password Reset Flow Completed" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration used:" -ForegroundColor Yellow
Write-Host "  Challenge Types: $challengeTypesString" -ForegroundColor Gray
Write-Host ""

# Clear the password from memory
$newPasswordPlain = $null
[System.GC]::Collect()

# Display configuration insights
Write-Host "Configuration Insights:" -ForegroundColor Magenta
Write-Host "  Using space-separated challenge types: '$challengeTypesString'" -ForegroundColor Green
Write-Host "  Authority configured correctly" -ForegroundColor Green
Write-Host "  Native authentication API flow completed" -ForegroundColor Green