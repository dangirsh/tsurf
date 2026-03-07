//! Entrypoint for secret-proxy.
//!
//! @decision(66-01): Secrets are read once at startup from files and retained in memory,
//! so sandboxed request handling never touches secret files and fails fast on bad config.

mod config;
mod proxy;

use std::{env, fs, net::SocketAddr, sync::Arc};

use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("secret_proxy=info".parse().unwrap()))
        .init();

    let args: Vec<String> = env::args().collect();
    let config_path = args
        .windows(2)
        .find(|window| window[0] == "--config")
        .map(|window| window[1].clone())
        .unwrap_or_else(|| {
            eprintln!("Usage: secret-proxy --config <path>");
            std::process::exit(1);
        });

    let config_str = fs::read_to_string(&config_path).unwrap_or_else(|err| {
        eprintln!("Cannot read config {}: {}", config_path, err);
        std::process::exit(1);
    });

    let config: config::Config = toml::from_str(&config_str).unwrap_or_else(|err| {
        eprintln!("Invalid config: {}", err);
        std::process::exit(1);
    });

    let loaded: Vec<proxy::LoadedSecret> = config
        .secret
        .iter()
        .map(|secret| {
            if secret.allowed_domains.is_empty() {
                eprintln!(
                    "Secret '{}' has empty allowed_domains (file: {})",
                    secret.name, secret.file
                );
                std::process::exit(1);
            }

            let key = fs::read_to_string(&secret.file).unwrap_or_else(|err| {
                eprintln!(
                    "Cannot read secret '{}' from {}: {}",
                    secret.name, secret.file, err
                );
                std::process::exit(1);
            });

            let key = key.trim().to_string();
            if key.is_empty() {
                eprintln!("Secret '{}' is empty (file: {})", secret.name, secret.file);
                std::process::exit(1);
            }

            let allowed_domains: Vec<String> = secret
                .allowed_domains
                .iter()
                .map(|domain| domain.trim().to_ascii_lowercase())
                .collect();

            let upstream_host = allowed_domains[0].clone();

            proxy::LoadedSecret {
                name: secret.name.clone(),
                header: secret.header.clone(),
                key,
                allowed_domains,
                upstream_host,
            }
        })
        .collect();

    let state = Arc::new(proxy::ProxyState {
        placeholder: config.placeholder.clone(),
        secrets: loaded,
        client: reqwest::Client::new(),
    });

    let app = proxy::make_router(state);
    let addr = SocketAddr::from(([127, 0, 0, 1], config.port));

    tracing::info!("secret-proxy listening on {}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
