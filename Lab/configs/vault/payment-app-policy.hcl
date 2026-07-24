path "transit/encrypt/payment-chd" {
  capabilities = ["update"]
}

path "transit/hmac/payment-token" {
  capabilities = ["update"]
}

path "transit/hmac/payment-token/*" {
  capabilities = ["update"]
}
