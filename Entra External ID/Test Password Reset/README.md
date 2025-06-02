# External ID SSPR API Testing Script

## Purpose

This PowerShell script enables quick testing of Microsoft Entra External ID's Self-Service Password Reset (SSPR) API without needing to build a Single Page Application first. It provides a simple command-line interface to test the complete SSPR flow with detailed request/response logging for debugging and validation.

## Quick Setup

### 1. Create App Registration

1. **Sign in** to the [Microsoft Entra admin center](https://entra.microsoft.com)
2. **Go to** Applications > App registrations > New registration
3. **Create** with name: `SSPR API Test App`
4. **Navigate to** Authentication > Settings tab
5. **Enable both**:
   - Allow native authentication
   - Allow public client flows
6. **Copy the Application (client) ID**

### 2. Configure Script

Update the configuration in the PowerShell script:

```powershell
$config = @{
    client_id = "YOUR_CLIENT_ID_HERE"              # From step 1
    tenant_subdomain = "YOUR_TENANT_SUBDOMAIN"     # e.g., "contoso"
    authorities = @(
        @{
            authority_url = "https://YOUR_TENANT_SUBDOMAIN.ciamlogin.com/YOUR_TENANT_SUBDOMAIN.onmicrosoft.com/"
        }
    )
    challenge_types = @("oob", "redirect")         # Required for SSPR
}
```

### 3. Prerequisites

- External ID tenant with SSPR enabled
- Test user with email/password authentication
- PowerShell 5.1 or later

## Usage

1. **Run the script**: `.\Test-PasswordReset.ps1`
2. **Enter user email** when prompted
3. **Check email** for OTP after Step 2
4. **Enter OTP code** when prompted
5. **Enter new password** when prompted

## SSPR Process Overview

The script tests the 4-step SSPR flow:

### Step 1: Start (`/resetpassword/v1.0/start`)
- Initiates password reset for the user
- Validates email address exists
- Returns continuation token

### Step 2: Challenge (`/resetpassword/v1.0/challenge`)
- Triggers OTP email to be sent
- Uses continuation token from Step 1
- Returns new continuation token

### Step 3: Continue (`/resetpassword/v1.0/continue`)
- Validates the OTP code from email
- Requires `grant_type=oob` parameter
- Returns final continuation token

### Step 4: Submit (`/resetpassword/v1.0/submit`)
- Accepts new password
- Completes the reset process
- Password is now changed

## Challenge Types

**Required for SSPR**: `oob redirect` (space-separated)

- **oob**: Out-of-band authentication (email OTP)
- **redirect**: Mandatory fallback for web-based auth if needed

The `redirect` challenge type is required by Microsoft for all native authentication flows.

## Common Issues

| Error | Cause | Solution |
|-------|-------|----------|
| `unsupported_challenge_type` (901007) | Missing `redirect` in challenge types | Use `oob redirect` (space-separated) |
| `nativeauthapi_disabled` | Native auth not enabled | Enable in app registration settings |
| `user_not_found` | User doesn't exist | Verify user exists in External ID tenant |
| `invalid_oob_value` | Wrong OTP code | Check email for correct OTP |
| `password_too_weak` | Password complexity | Use stronger password |

## Sample Output

```
========================================
 External ID Password Reset Flow Test
========================================

Step 1: Starting password reset flow...

===========================================
 STEP 1: START
===========================================

URL:
  https://contoso.ciamlogin.com/contoso.onmicrosoft.com/resetpassword/v1.0/start

Request Body:
  client_id = ce65863c-6ed6-41c3-b16c-d9df898714f3
  challenge_type = oob redirect
  username = user@example.com

Response:
  continuation_token = AQABIgEAAABVrSpeuWamRam2jAF1XRQEp1cE...

SUCCESS: Password reset flow started!
```

## API Endpoints Reference

| Endpoint | Purpose |
|----------|---------|
| `/resetpassword/v1.0/start` | Initiate password reset |
| `/resetpassword/v1.0/challenge` | Send OTP email |
| `/resetpassword/v1.0/continue` | Validate OTP |
| `/resetpassword/v1.0/submit` | Set new password |

## Resources

- [Native Authentication API Reference](https://learn.microsoft.com/en-us/entra/identity-platform/reference-native-authentication-api)
- [Challenge Types Documentation](https://learn.microsoft.com/en-us/entra/identity-platform/concept-native-authentication-challenge-types)
- [React SSPR Tutorial](https://learn.microsoft.com/en-us/entra/identity-platform/tutorial-native-authentication-single-page-app-react-reset-password)