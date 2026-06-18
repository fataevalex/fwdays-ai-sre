# ArgoCD OIDC Authentication via Keycloak

## Overview

ArgoCD v3.0.6 configured for SSO via Keycloak (realm `homelab`).
Access is restricted to members of Keycloak group `argocd` (mapped to `role:admin`).
All other authenticated users are denied.

## What was configured

### Keycloak group `argocd`

Created group `argocd` in realm `homelab`. Members get `role:admin` in ArgoCD.

To add a user to the group via API:
```bash
TOKEN=$(curl -s -X POST "https://keycloak.fataev.in.ua/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli&grant_type=password&username=<user>&password=<pass>" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

GROUP_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "https://keycloak.fataev.in.ua/admin/realms/homelab/groups?search=argocd" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

USER_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "https://keycloak.fataev.in.ua/admin/realms/homelab/users?email=<email>" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

curl -s -o /dev/null -w "%{http_code}" -X PUT \
  "https://keycloak.fataev.in.ua/admin/realms/homelab/users/$USER_ID/groups/$GROUP_ID" \
  -H "Authorization: Bearer $TOKEN"
```

### Keycloak client `argocd`

Created via Keycloak Admin API in realm `homelab`:

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
  g, argocd, role:admin
policy.default: role:''
scopes: '[email, groups]'
```

> **Note:** Keycloak sends group names **without** a leading slash (e.g., `argocd`, not `/argocd`).
> Using `/argocd` in the policy will silently break group mapping.

### Traefik IngressRoute fix

Removed `argocd-logout-redirect-fix` middleware from the IngressRoute.
It was overriding the `Location` response header on **all** responses, which broke
the OIDC redirect to Keycloak. With `url` properly set in `argocd-cm`, ArgoCD v3
handles base path redirects correctly without this workaround.

Applied manually via kubectl (IngressRoute is not in this repo):
```bash
kubectl patch ingressroute argocd-server-ingressroute -n argocd --type=json \
  -p='[{"op":"replace","path":"/spec/routes/0/middlewares","value":[{"name":"argocd-strip-prefix","namespace":"argocd"}]}]'
```

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
| Logged in but no applications visible | Group mapping broken — check group name has no leading slash | Use `argocd` not `/argocd` in `argocd-rbac-cm` |
