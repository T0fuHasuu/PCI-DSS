# Demo-only controlled verification. This policy is assigned only when
# DEMO_EVIDENCE_ENABLED=true. Routine payment processing does not need decrypt.
path "transit/decrypt/payment-chd" {
  capabilities = ["update"]
}
