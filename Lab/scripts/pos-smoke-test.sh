#!/bin/sh
set -eu

CURL='curl --fail --show-error --silent --tlsv1.2 --tls-max 1.2 --cacert /etc/lab/pki/ca.crt'

echo '[1/2] Health'
sh -c "$CURL https://payment.gateway/health"
echo

echo '[2/2] Test transaction'
sh -c "$CURL -H 'Content-Type: application/json' -d '{\"customer\":{\"full_name\":\"Lab User\",\"email\":\"lab@example.test\",\"phone_number\":\"+85510000000\"},\"card\":{\"pan\":\"4111111111111111\",\"exp_month\":12,\"exp_year\":2030,\"cvv\":\"123\"},\"amount\":25.50}' https://payment.gateway/process-transaction"
echo
