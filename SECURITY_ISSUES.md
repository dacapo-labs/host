# Security Issues to Create

No GitHub token available in environment. Create these issues manually at:
- https://github.com/dacapo-labs/baton/issues/new
- https://github.com/dacapo-labs/host/issues/new

---

## Baton Repository Issues

### Issue 1: [Security] Remove 0.0.0.0 binding example from README
**Priority:** High
**Labels:** security, documentation

**Description:**
The README currently shows examples using `--host 0.0.0.0` which binds to all network interfaces. Even with Tailscale, this creates unnecessary exposure.

**Current:**
```bash
uvicorn baton.server:app --host 0.0.0.0 --port 4000
```

**Recommended:**
```bash
uvicorn baton.server:app --host 127.0.0.1 --port 4000
```

**Risk:** If run outside the Tailscale network or if Tailscale is misconfigured, the service would be exposed to all network interfaces.

---

### Issue 2: [Security] Add API authentication to baton endpoints
**Priority:** High
**Labels:** security, enhancement

**Description:**
Baton endpoints currently have no authentication. While the service runs behind Tailscale, defense-in-depth suggests adding an authentication layer.

**Recommendations:**
1. Add Bearer token authentication for API endpoints
2. Token can be stored in config file with restricted permissions (600)
3. Optional: Support for multiple tokens for different clients
4. Exclude health endpoint (`/health`) from auth requirement

**Example implementation:**
```python
from fastapi import Depends, HTTPException, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

security = HTTPBearer()

async def verify_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    if credentials.credentials != settings.api_token:
        raise HTTPException(status_code=401, detail="Invalid token")
    return credentials.credentials
```

---

### Issue 3: [Security] Add SSM resource allowlist/filtering
**Priority:** High
**Labels:** security, enhancement

**Description:**
The SSM plugin currently allows access to any SSM parameter or secret. Add configuration to limit accessible resources.

**Recommendations:**
1. Add `allowed_paths` config for SSM parameters (e.g., `/myapp/*`)
2. Add `allowed_secrets` config for Secrets Manager
3. Default to deny-all if no allowlist configured
4. Log denied access attempts

**Example config:**
```toml
[plugins.ssm]
enabled = true
allowed_parameter_paths = ["/myapp/", "/shared/config/"]
allowed_secret_prefixes = ["myapp-", "shared-"]
deny_by_default = true
```

---

### Issue 4: [Security] Add log sanitization for sensitive data
**Priority:** Medium
**Labels:** security, enhancement

**Description:**
Ensure logs don't contain sensitive information that could be exposed if logs are accessed.

**Recommendations:**
1. Redact Authorization headers in request logs
2. Redact SSM parameter values in debug logs
3. Redact secret values from Secrets Manager
4. Add configurable patterns for additional redaction

**Patterns to redact:**
- `Bearer [token]` → `Bearer [REDACTED]`
- API keys matching common patterns
- AWS credentials
- Password fields

---

### Issue 5: [Security] Add SSM usage audit logging
**Priority:** Medium
**Labels:** security, observability

**Description:**
Add structured audit logging for SSM operations to support security monitoring.

**Log format:**
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "action": "ssm:GetParameter",
  "resource": "/myapp/database/connection",
  "client_ip": "100.64.0.1",
  "result": "success"
}
```

**Recommendations:**
1. Log all SSM read operations
2. Log denied access attempts
3. Support forwarding to external logging (CloudWatch, file)
4. Include client identification when possible

---

### Issue 6: [Security] Add session timeout for credentials cache
**Priority:** Medium
**Labels:** security, enhancement

**Description:**
If baton caches any credentials or sessions, ensure they have appropriate timeouts.

**Recommendations:**
1. SSM credentials should use AWS SDK default expiration
2. Any local caching should have configurable TTL
3. Default TTL should be short (15 minutes)
4. Provide endpoint to clear cache if needed

---

### Issue 7: [Security] Document mTLS setup for network exposure
**Priority:** Low
**Labels:** security, documentation

**Description:**
For environments where baton might be exposed beyond localhost, document mTLS setup.

**Recommendations:**
1. Document nginx/caddy reverse proxy with mTLS
2. Provide example certificates generation script
3. Note that this is only needed if not using Tailscale
4. Keep as documentation only - don't add complexity to baton itself

---

## Host Repository Issues

### Issue 8: [Security] Consider Terraform state encryption options
**Priority:** Low
**Labels:** security, infrastructure

**Description:**
Review Terraform state storage for sensitive data exposure.

**Current state:**
- State likely contains Tailscale auth keys (marked sensitive)
- Bitwarden credentials used during provisioning
- EC2 instance details

**Recommendations:**
1. Document if using S3 backend with encryption
2. Consider state encryption at rest
3. Review what sensitive values are stored in state
4. Add `.gitignore` entry for `*.tfstate*` if local

**Note:** This is lower priority since:
- Tailscale keys can be rotated
- Instance itself has strong security (LUKS, no public ingress)
- State access requires AWS credentials

---

## Summary

| Issue | Repo | Priority | Type |
|-------|------|----------|------|
| Remove 0.0.0.0 from README | baton | High | Doc fix |
| API authentication | baton | High | Enhancement |
| SSM allowlist | baton | High | Enhancement |
| Log sanitization | baton | Medium | Enhancement |
| Audit logging | baton | Medium | Enhancement |
| Session timeout | baton | Medium | Enhancement |
| mTLS documentation | baton | Low | Documentation |
| Terraform state | host | Low | Documentation |

## Discussion Points

1. **API Authentication**: Should this be optional (for dev) or always required?
2. **SSM Allowlist**: What's the expected use case - broad access or restricted?
3. **Audit Logging**: Where should logs go - file, stdout, CloudWatch?
4. **Priority**: Which issues should be addressed before production use?
