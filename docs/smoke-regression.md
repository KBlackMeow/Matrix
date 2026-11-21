# Matrix Minimal Smoke Regression

## Scope

- Project management
- Webshell CRUD and entry to interactive page
- Payload and dictionary management
- Vulhub page entry actions

## Quick Automated Checks

- `flutter test`
- `flutter analyze lib/exp/thinkphp/thinkphp_exp_service.dart lib/exp/thinkphp/thinkphp_v5_exp.dart lib/exp/thinkphp/thinkphp_v6_exp.dart`

## Manual Checklist

- Project management: create/edit/delete a project.
- Webshell management: create/edit/delete a webshell under a selected project.
- Webshell interaction: open one record and verify page loads and command panel is responsive.
- Payload management: create/edit/delete one payload and verify list refreshes.
- Dictionary management: create/edit/delete one dictionary entry and verify list refreshes.
- Vulhub entries: open each Vulhub EXP page from `EXP管理` and trigger one basic detection action per page.

## Pass Criteria

- No crash during each operation.
- UI state updates after create/edit/delete.
- Navigation to target pages succeeds.
- Detection actions return logs or expected error messages without blocking the UI.

## Tunnel Integration (opt-in, Docker)

These tests are skipped unless the matching environment variables are set.

### FRP

Start a local frps:

```bash
cat >/tmp/frps.toml <<'TOML'
bindPort = 17000
auth.method = "token"
auth.token = "matrix-test-token"
TOML
docker run -d --name mx-frps \
  -p 17000:17000 -p 16000:16000 \
  -v /tmp/frps.toml:/etc/frp/frps.toml \
  snowdreamtech/frps:latest
```

Run:

```bash
MATRIX_FRP_SERVER=127.0.0.1 \
MATRIX_FRP_PORT=17000 \
MATRIX_FRP_TOKEN=matrix-test-token \
MATRIX_FRP_REMOTE_PORT=16000 \
flutter test test/services/frp_integration_test.dart
```

### SUO5 / SUO6

Deploy `assets/defaults/payloads/suo5/*` and `assets/defaults/payloads/suo6/*`
to PHP/Tomcat, then run:

```bash
# deploy a small static file as the SOCKS target
printf 'SUO_TARGET_OK' >/tmp/suo_target.txt
docker cp /tmp/suo_target.txt mx-suo-php:/var/www/html/suo_target.txt
docker cp /tmp/suo_target.txt mx-suo-tomcat:/usr/local/tomcat/webapps/ROOT/suo_target.txt

MATRIX_SUO5_URL=http://127.0.0.1:18098/suo5.php \
MATRIX_SUO5_TARGET=127.0.0.1:80 \
MATRIX_SUO5_PATH=/suo_target.txt \
MATRIX_SUO5_JSP_URL=http://127.0.0.1:18097/suo5.jsp \
MATRIX_SUO5_JSP_TARGET=127.0.0.1:8080 \
MATRIX_SUO5_JSP_PATH=/suo_target.txt \
MATRIX_SUO6_URL=http://127.0.0.1:18097/suo6.jsp \
MATRIX_SUO6_TARGET=127.0.0.1:8080 \
MATRIX_SUO6_PATH=/suo_target.txt \
flutter test test/services/suo_integration_test.dart
```

The target address is resolved by the WebShell payload, not by the test host.
For Docker Desktop, a container usually cannot reach the host through
`127.0.0.1`; use an address reachable from the container or target a service
inside the same container (as above).
