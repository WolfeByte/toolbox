# External ID SSPR API Testing Script

## Purpose

This PowerShell script enables quick testing of Microsoft Entra External ID's Self-Service Password Reset (SSPR) API without needing to build a Single Page Application first. It provides a simple command-line interface to test the complete SSPR flow with detailed request/response output for debugging and validation.

![Image](https://github.com/user-attachments/assets/7ae281fc-bfde-40d8-866f-bd2dc7c2d219)

### 1. Prerequisites

- An External ID tenant
- Email one-time passcode (Email OTP) authentication method enabled for all users
- A sign-up user flow with **Email with password** as an authentication method under Identity providers.
- A Test user created in the tenant with valid email address
- PowerShell 7.1 or later


## Quick Setup

### 2. Create App Registration

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
- Validates user exists in the tenant
- Returns continuation token

### Step 2: Challenge (`/resetpassword/v1.0/challenge`)
- Triggers OTP email to be sent
- Uses continuation token from Step 1
- Returns new continuation token

### Step 3: Continue (`/resetpassword/v1.0/continue`)
- Validates the OTP code from email
- Includes required `grant_type=oob` parameter
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


## API Endpoints Reference

| Endpoint | Purpose |
|----------|---------|
| `/resetpassword/v1.0/start` | Initiate password reset |
| `/resetpassword/v1.0/challenge` | Send OTP email |
| `/resetpassword/v1.0/continue` | Validate OTP |
| `/resetpassword/v1.0/submit` | Set new password |

## Resources

- [Enable self-service password reset](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-enable-password-reset-customers)
- [Native Authentication API Reference](https://learn.microsoft.com/en-us/entra/identity-platform/reference-native-authentication-api)
- [Challenge Types Documentation](https://learn.microsoft.com/en-us/entra/identity-platform/concept-native-authentication-challenge-types)
- [React SSPR Tutorial](https://learn.microsoft.com/en-us/entra/identity-platform/tutorial-native-authentication-single-page-app-react-reset-password)
