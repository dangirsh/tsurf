//! HTTP->HTTPS forwarding proxy with host allowlist and per-secret header injection.
//!
//! @decision(66-01): The destination upstream is always `allowed_domains[0]` for the
//! matched secret, so sandboxed clients cannot redirect traffic by changing request URLs.

use std::sync::Arc;

use axum::{
    body::Body,
    extract::{Request, State},
    http::{HeaderMap, HeaderName, HeaderValue, StatusCode},
    response::Response,
    routing::any,
    Router,
};
use tracing::{error, info, warn};

const REQUEST_SKIP_HEADERS: &[&str] = &[
    "x-api-key",
    "authorization",
    "host",
    "content-length",
    "transfer-encoding",
];

const RESPONSE_SKIP_HEADERS: &[&str] = &["transfer-encoding", "connection"];

#[derive(Clone, Debug)]
pub struct LoadedSecret {
    pub name: String,
    pub header: String,
    pub key: String,
    pub allowed_domains: Vec<String>,
    pub upstream_host: String,
}

#[derive(Clone)]
pub struct ProxyState {
    pub placeholder: String,
    pub secrets: Vec<LoadedSecret>,
    pub client: reqwest::Client,
}

pub fn make_router(state: Arc<ProxyState>) -> Router {
    Router::new()
        .route("/", any(proxy_handler))
        .route("/*path", any(proxy_handler))
        .with_state(state)
}

async fn proxy_handler(State(state): State<Arc<ProxyState>>, request: Request) -> Response {
    let (parts, body) = request.into_parts();
    let host = match extract_host(&parts.headers) {
        Some(host) => host,
        None => {
            warn!("DENY host=<missing> secret_name=<none>");
            return forbidden();
        }
    };

    let Some(secret) = state
        .secrets
        .iter()
        .find(|secret| secret.allowed_domains.iter().any(|domain| domain == &host))
    else {
        warn!("DENY host={} secret_name=<none>", host);
        return forbidden();
    };

    let secret_header_name = match HeaderName::from_bytes(secret.header.as_bytes()) {
        Ok(name) => name,
        Err(err) => {
            error!(
                "invalid configured header '{}' for secret '{}': {}",
                secret.header, secret.name, err
            );
            return simple_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Proxy misconfiguration: invalid secret header\n",
            );
        }
    };

    if let Some(existing) = parts.headers.get(&secret_header_name) {
        match existing.to_str() {
            Ok(v) if v == state.placeholder => {}
            Ok(v) => warn!(
                "secret header '{}' for '{}' does not match configured placeholder (value='{}')",
                secret.header, secret.name, v
            ),
            Err(_) => warn!(
                "secret header '{}' for '{}' is not valid utf-8",
                secret.header, secret.name
            ),
        }
    }

    let mut forward_headers = HeaderMap::new();
    for (name, value) in &parts.headers {
        if should_skip_request_header(name.as_str()) {
            continue;
        }
        forward_headers.append(name, value.clone());
    }

    let secret_value = match HeaderValue::from_str(&secret.key) {
        Ok(value) => value,
        Err(err) => {
            error!("invalid secret value for '{}' header '{}': {}", secret.name, secret.header, err);
            return simple_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Proxy misconfiguration: invalid secret value\n",
            );
        }
    };
    forward_headers.insert(secret_header_name, secret_value);

    let path_and_query = parts
        .uri
        .path_and_query()
        .map(|pq| pq.as_str())
        .unwrap_or("/");
    let target_url = format!("https://{}{}", secret.upstream_host, path_and_query);

    info!(
        "ALLOW method={} host={} secret_name={} upstream={}",
        parts.method, host, secret.name, secret.upstream_host
    );

    let upstream_response = match state
        .client
        .request(parts.method, target_url)
        .headers(forward_headers)
        .body(reqwest::Body::wrap_stream(body.into_data_stream()))
        .send()
        .await
    {
        Ok(resp) => resp,
        Err(err) => {
            error!(
                "upstream request failed host={} secret_name={} error={}",
                host, secret.name, err
            );
            return simple_response(StatusCode::BAD_GATEWAY, "Upstream request failed\n");
        }
    };

    let status = upstream_response.status();
    let upstream_headers = upstream_response.headers().clone();
    let upstream_stream = upstream_response.bytes_stream();

    let mut response = Response::new(Body::from_stream(upstream_stream));
    *response.status_mut() = status;

    for (name, value) in &upstream_headers {
        if should_skip_response_header(name.as_str()) {
            continue;
        }
        response.headers_mut().append(name, value.clone());
    }

    response
}

fn extract_host(headers: &HeaderMap) -> Option<String> {
    let host = headers.get("host")?.to_str().ok()?.trim();
    if host.is_empty() {
        return None;
    }

    // Host header may include a port (`example.com:443`). Strip it before allowlist match.
    let normalized = host.split(':').next().unwrap_or(host).to_ascii_lowercase();
    if normalized.is_empty() {
        None
    } else {
        Some(normalized)
    }
}

fn forbidden() -> Response {
    simple_response(
        StatusCode::FORBIDDEN,
        "Access denied: host not in allowlist\n",
    )
}

fn simple_response(status: StatusCode, body: &'static str) -> Response {
    let mut response = Response::new(Body::from(body));
    *response.status_mut() = status;
    response
}

fn should_skip_request_header(header: &str) -> bool {
    REQUEST_SKIP_HEADERS
        .iter()
        .any(|item| header.eq_ignore_ascii_case(item))
}

fn should_skip_response_header(header: &str) -> bool {
    RESPONSE_SKIP_HEADERS
        .iter()
        .any(|item| header.eq_ignore_ascii_case(item))
}
