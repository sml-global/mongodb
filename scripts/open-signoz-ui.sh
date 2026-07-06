#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
	open-signoz-ui.sh [--mode <port-forward|ingress>] [options]

Modes:
	--mode port-forward   Open local tunnel to service (dev only)
	--mode ingress        Print SigNoz ingress URL (production preferred)

Port-forward options:
	--namespace <name>    Kubernetes namespace (default: signoz)
	--service <name>      Service name (default: signoz)
	--local-port <port>   Local bind port (default: 3301)
	--remote-port <port>  Service target port (default: 8080)

Ingress options:
	--ingress <name>      Ingress name (default: signoz)
	--open                Open URL in browser after printing

Examples:
	scripts/open-signoz-ui.sh
	scripts/open-signoz-ui.sh --mode ingress --namespace signoz --ingress signoz
EOF
}

MODE="port-forward"
NAMESPACE="signoz"
SERVICE="signoz"
LOCAL_PORT="3301"
REMOTE_PORT="8080"
INGRESS_NAME="signoz"
OPEN_BROWSER="false"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--mode)
			MODE="${2:-}"
			shift 2
			;;
		--namespace)
			NAMESPACE="${2:-}"
			shift 2
			;;
		--service)
			SERVICE="${2:-}"
			shift 2
			;;
		--local-port)
			LOCAL_PORT="${2:-}"
			shift 2
			;;
		--remote-port)
			REMOTE_PORT="${2:-}"
			shift 2
			;;
		--ingress)
			INGRESS_NAME="${2:-}"
			shift 2
			;;
		--open)
			OPEN_BROWSER="true"
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Error: unknown argument '$1'" >&2
			usage
			exit 1
			;;
	esac
done

if [[ "$MODE" == "port-forward" ]]; then
	echo "Warning: port-forward is intended for local development and break-glass troubleshooting only." >&2
	echo "Opening SigNoz UI tunnel from ${NAMESPACE}/${SERVICE} ${LOCAL_PORT}->${REMOTE_PORT}"
	kubectl -n "$NAMESPACE" port-forward "svc/$SERVICE" "$LOCAL_PORT:$REMOTE_PORT"
	exit 0
fi

if [[ "$MODE" == "ingress" ]]; then
	host="$(kubectl -n "$NAMESPACE" get ingress "$INGRESS_NAME" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || true)"
	if [[ -z "$host" ]]; then
		echo "Error: no ingress host found for ${NAMESPACE}/${INGRESS_NAME}." >&2
		echo "Hint: expose SigNoz in production through an ingress controller (ALB or NGINX) and secure it with SSO/OIDC + network policy." >&2
		exit 1
	fi

	tls_secret="$(kubectl -n "$NAMESPACE" get ingress "$INGRESS_NAME" -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null || true)"
	scheme="http"
	if [[ -n "$tls_secret" ]]; then
		scheme="https"
	fi

	url="${scheme}://${host}"
	echo "$url"

	if [[ "$OPEN_BROWSER" == "true" ]]; then
		if command -v open >/dev/null 2>&1; then
			open "$url"
		else
			echo "Info: 'open' command not found; copy URL manually." >&2
		fi
	fi
	exit 0
fi

echo "Error: unsupported mode '$MODE'. Use --mode port-forward or --mode ingress." >&2
exit 1
