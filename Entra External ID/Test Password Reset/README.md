# External ID SSPR API Testing Script

A PowerShell script that enables quick testing of Microsoft Entra External ID's Self-Service Password Reset (SSPR) API without needing to build a Single Page Application first.

## Overview

Testing the Self-Service Password Reset flow for Microsoft Entra External ID typically requires building a complete Single Page Application or diving deep into complex API documentation. This creates a significant barrier when you just need to validate that your SSPR configuration is working correctly or troubleshoot authentication issues.

This script eliminates that complexity by providing a **simple command-line interface** that walks through the complete 4-step SSPR flow with detailed request/response output for debugging and validation. Perfect for developers who need to quickly test their External ID tenant configuration or understand how the SSPR API works in practice.

Whether you're setting up SSPR for the first time, troubleshooting authentication issues, or just need to validate your tenant configuration, this script provides an interactive way to test the complete password reset flow without writing a single line of frontend code.

![Image](https://github.com/user-attachments/assets/7ae281fc-bfde-40d8-866f-bd2dc7c2d219)

With this script you can:

* **Test the complete SSPR flow** through all 4 API endpoints with detailed logging
* **Validate tenant configuration** for External ID Self-Service Password Reset
* **Debug authentication issues** with comprehensive request/response output
* **Understand the SSPR API** through interactive testing without building an SPA

## Key Features

* **Interactive Testing**: Step-by-step guidance through the complete SSPR flow
* **Detailed Logging**: Full request/response output for debugging and validation
* **Configuration Validation**: Automatic checks for common setup issues
* **Error Troubleshooting**: Clear error messages with suggested solutions
* **No Frontend Required**: Test SSPR without building a Single Page Application

## Prerequisites

* **PowerShell 7.1 or higher**
* **Microsoft Entra External ID tenant**
* **Required External ID configuration**:
  - Email one-time passcode (Email OTP) authentication method enabled for all users
  - A sign-up user flow with **Email with password** as an authentication method
  - A test external user created in the tenant with a valid email address

## Installation

1. **Create an App Registration** in your External ID tenant:
   - Sign in to the [Microsoft Entra admin center](https://entra.microsoft.com)
   - Go to Applications > App registrations > New registration
   - Create with name: `SSPR API Test App`
   - Navigate to Authentication > Settings tab
   - Enable both:
     - Allow native authentication
     - Allow public client flows
   - Copy the Application (client) ID

2. **Configure the script** with your tenant details:
   
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

3. **Run the script**:

   ```powershell
   .\Test-PasswordReset.ps1
   ```

## Usage

The script provides an **interactive interface** for testing the complete SSPR flow:

### Testing Process

1. **Start the script**: `.\Test-PasswordReset.ps1`
2. **Enter user email** when prompted (must be a valid user in your External ID tenant)
3. **Check email** for OTP code after Step 2 completes
4. **Enter OTP code** when prompted by the script
5. **Enter new password** when prompted (must meet complexity requirements)
6. **Review results** - the script shows detailed API responses for each step

### SSPR Flow Steps

The script tests all 4 required SSPR API endpoints:

| Step | Endpoint | Purpose |
|------|----------|---------|
| 1 | `/resetpassword/v1.0/start` | Initiates password reset and validates user exists |
| 2 | `/resetpassword/v1.0/challenge` | Triggers OTP email to be sent to user |
| 3 | `/resetpassword/v1.0/continue` | Validates the OTP code from email |
| 4 | `/resetpassword/v1.0/submit` | Accepts new password and completes reset |

## Configuration Reference

### Challenge Types

**Required for SSPR**: `oob redirect` (space-separated)

| Challenge Type | Description |
|----------------|-------------|
| `oob` | Out-of-band authentication (email OTP) |
| `redirect` | Mandatory fallback for web-based auth flows |

The `redirect` challenge type is required by Microsoft for all native authentication flows, even when not directly used.

### Common Configuration Issues

| Error Code | Description | Solution |
|------------|-------------|----------|
| `unsupported_challenge_type` (901007) | Missing `redirect` in challenge types | Use `oob redirect` (space-separated) |
| `nativeauthapi_disabled` | Native auth not enabled | Enable in app registration Authentication settings |
| `user_not_found` | User doesn't exist in tenant | Verify user exists in External ID tenant |
| `invalid_oob_value` | Wrong OTP code entered | Check email for correct OTP code |
| `password_too_weak` | Password doesn't meet complexity | Use stronger password with mixed case, numbers, symbols |

## API Reference

### SSPR Endpoints

All endpoints use the base URL: `https://{tenant-subdomain}.ciamlogin.com/{tenant-subdomain}.onmicrosoft.com`

| Endpoint | Method | Purpose | Required Parameters |
|----------|--------|---------|-------------------|
| `/resetpassword/v1.0/start` | POST | Initiate password reset | `client_id`, `username` |
| `/resetpassword/v1.0/challenge` | POST | Send OTP email | `client_id`, `challenge_type`, `continuation_token` |
| `/resetpassword/v1.0/continue` | POST | Validate OTP | `client_id`, `grant_type`, `oob_code`, `continuation_token` |
| `/resetpassword/v1.0/submit` | POST | Set new password | `client_id`, `new_password`, `continuation_token` |

### Response Format

Each endpoint returns a JSON response with:
- `continuation_token`: Used for the next step in the flow
- `challenge_type`: Type of authentication challenge
- Additional metadata specific to each step

## Troubleshooting

### Setup Issues

If you encounter setup-related errors, verify:

1. **App Registration Configuration**:
   - Native authentication is enabled
   - Public client flows are allowed
   - Application ID is correct

2. **Tenant Configuration**:
   - Email OTP is enabled for all users
   - Sign-up user flow includes "Email with password"
   - Test user exists with valid email address

3. **Script Configuration**:
   - Tenant subdomain matches your External ID tenant
   - Challenge types include both "oob" and "redirect"
   - Authority URL format is correct

### API Errors

The script provides detailed error information including:
- HTTP status codes
- Error messages from the API
- Suggested solutions for common issues
- Full request/response details for debugging

## Contributing

If you have suggestions or improvements, feel free to submit a pull request or open an issue.

## References

* [Enable Self-Service Password Reset](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-enable-password-reset-customers)
* [Native Authentication API Reference](https://learn.microsoft.com/en-us/entra/identity-platform/reference-native-authentication-api)
* [Challenge Types Documentation](https://learn.microsoft.com/en-us/entra/identity-platform/concept-native-authentication-challenge-types)
* [React SSPR Tutorial](https://learn.microsoft.com/en-us/entra/identity-platform/tutorial-native-authentication-single-page-app-react-reset-password)
* [Microsoft Entra External ID Documentation](https://learn.microsoft.com/en-us/entra/external-id/)

## License

This project is licensed under the MIT License - see the LICENSE file for details.

---
