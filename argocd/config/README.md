# ArgoCD OIDC Authentication via Keycloak

## Overview

ArgoCD v3.0.6 configured for SSO via Keycloak (realm `homelab`).
User `fataevalex@gmail.com` has `role:admin`.

## What was configured

### Keycloak client `argocd`

Created manually via Keycloak Admin API in realm `homelab`:

| Parameter | Value |
|-----------|-------|
| Client ID | `argocd` |
| Access type | confidential |
| Valid redirect URIs | `https://minipc.local/argocd/auth/callback` |
| Optional client scopes | `groups` (required — must be added explicitly) |

Client secret is stored in k8s secret `argocd-secret` (namespace `argocd`) under key `oidc.keycloak.clientSecret`.
Applied manually via kubectl (not in git — contains sensitive value).

### `argocd-cm` (`argocd-cm-patch.yaml`)

```yaml
url: https://minipc.local/argocd
oidc.config: |
  name: Keycloak
  issuer: https://keycloak.fataev.in.ua/realms/homelab
  clientID: argocd
  clientSecret: $oidc.keycloak.clientSecret
  requestedScopes:
    - openid
    - profile
    - email
    - groups
```

### `argocd-rbac-cm` (`argocd-rbac-cm.yaml`)

```yaml
policy.csv: |
  g, fataevalex@gmail.com, role:admin
policy.default: role:readonly
scopes: '[email, groups]'
```

### Traefik IngressRoute fix

Removed `argocd-logout-redirect-fix` middleware from the IngressRoute.
It was overriding the `Location` response header on **all** responses, which broke
the OIDC redirect to Keycloak. With `url` properly set in `argocd-cm`, ArgoCD v3
handles base path redirects correctly without this workaround.

Applied manually via kubectl patch (IngressRoute is not in this repo).

## How to recreate the client secret

```bash
TOKEN=$(curl -s -X POST "https://keycloak.fataev.in.ua/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli&grant_type=password&username=<user>&password=<pass>" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

CLIENT_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "https://keycloak.fataev.in.ua/admin/realms/homelab/clients?clientId=argocd" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://keycloak.fataev.in.ua/admin/realms/homelab/clients/$CLIENT_ID/client-secret" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['value'])"

# Apply to cluster:
kubectl patch secret argocd-secret -n argocd \
  --type=merge \
  -p '{"stringData": {"oidc.keycloak.clientSecret": "<secret>"}}'
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `invalid_scope: Invalid scopes: groups` | `groups` scope not added to Keycloak client | Add `groups` as optional client scope in Keycloak |
| Login starts but callback never completes | `Location` header overridden by Traefik middleware | Remove `argocd-logout-redirect-fix` from IngressRoute |
| Login button missing | `oidc.config` not in `argocd-cm` or argocd-server not restarted | Check `argocd-cm`, restart `argocd-server` deployment |
