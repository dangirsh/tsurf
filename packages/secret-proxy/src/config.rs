//! TOML configuration schema for secret-proxy.

use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Config {
    pub port: u16,
    pub placeholder: String,
    #[serde(default)]
    pub secret: Vec<SecretConfig>,
}

#[derive(Debug, Deserialize)]
pub struct SecretConfig {
    /// Request header to inject (e.g. "x-api-key" or "authorization")
    pub header: String,
    /// Human-readable name for logging
    pub name: String,
    /// Path to file containing the real secret value
    pub file: String,
    /// Exact domain names that are allowed (Host header match)
    pub allowed_domains: Vec<String>,
}
