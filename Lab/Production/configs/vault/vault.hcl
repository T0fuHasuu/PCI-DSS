ui = false
disable_mlock = true
log_level = "info"
log_format = "json"
api_addr = "https://vault.internal:8200"

storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_cert_file = "/vault/tls/server.crt"
  tls_key_file = "/vault/tls/server.key"
  tls_client_ca_file = "/vault/tls/ca.crt"
  tls_require_and_verify_client_cert = true
  tls_min_version = "tls12"
  tls_max_version = "tls12"
  tls_cipher_suites = "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
}
