[+] Re-Construct Container
docker compose down && docker compose up -d

[+] Rebuilding Container
docker compose up -d --build

[+] Remove Exisiting Endpoints
docker compose down --remove-orphans

[+] Hard Reset && Reboot
docker compose down -v
docker network prune -f
docker compose up -d --build

[+] Testing Application Server
docker exec -it app-server ping -c 1 10.100.20.10
docker exec -it app-server ping -c 1 10.100.30.10
docker exec -it app-server ping -c 1 kms
docker exec -it app-server ping -c 1 db

[+] Database Testing
docker exec -it db ping -c 1 app-server
docker exec -it db ping -c 1 10.100.10.10

[+] KMS Testing
docker exec -it kms ping -c 1 app-server
docker exec -it kms ping -c 1 10.100.10.10

[+] Connection KMS - DB
docker exec -it kms ping -c 1 db

[+] Testing Log ( UDP )
echo "test log event" | nc -u 10.200.10.10 514

[+] Access Database
docker-compose exec postgres psql -U cde_user -d cde_db

[+] Query Transactions
docker-compose exec postgres psql -U cde_user -d cde_db -c "SELECT * FROM transactions;"

[+] View Logs
docker-compose logs -f

[+] Certificate 
openssl req -x509 -nodes -days 365 -newkey rsa:2048 ^
  -keyout certs\peri\tls.key ^
  -out certs\peri\tls.crt ^
  -subj "/CN=payment.lab.local"

[🚀]
- Use only Name Resolutions


C:\Users\t0fu>curl -X POST http://localhost:8000/process-transaction ^
More?   -H "Content-Type: application/json" ^
More?   -d "{\"customer\": {\"full_name\": \"Test User\", \"email\": \"test@example.com\", \"phone_number\": \"+12025551234\"}, \"card\": {\"pan\": \"4532123456789999\", \"exp_month\": 12, \"exp_year\": 2026, \"cvv\": \"123\"}, \"amount\": 99.99}" | jq
  % Total    % Received % Xferd  Average Speed  Time    Time    Time   Current
                                 Dload  Upload  Total   Spent   Left   Speed
100    246 100     42 100    204    793   3853                              0
{
  "detail": "Transaction processing failed"
}


curl -X POST http://localhost:8000/process-transaction ^
  -H "Content-Type: application/json" ^
  -d "{\"customer\": {\"full_name\": \"Test User\", \"email\": \"test@example.com\", \"phone_number\": \"+12025551234\"}, \"card\": {\"pan\": \"4532123456789999\", \"exp_month\": 12, \"exp_year\": 2026, \"cvv\": \"123\"}, \"amount\": 99.99}" | jq



Your data is stored in the PostgreSQL container:

```
cde-postgres
```

Access it with:

```bash
docker exec -it cde-postgres psql -U cde_user -d cde_db
```

Then check tables:

```sql
\dt
```

You should see:

```
customers
transactions
```

Check customers:

```sql
SELECT * FROM customers;
```

Check transactions:

```sql
SELECT * FROM transactions;
```

You should see something like:

### customers

```
customer_id | full_name  | email              | phone_number
------------+------------+--------------------+-------------
1           | Test User  | test@example.com   | +12025551234
```

### transactions

```
tx_id | customer_id | tx_amount | masked_pan       | card_token
------+-------------+-----------+------------------+--------------------
3     | 1           | 99.99     | ************9999 | tok_ad526e25eea54456
```

The encrypted CHD is stored here:

```sql
SELECT encrypted_chd FROM transactions;
```

It should look like:

```
gAAAAABqLk...
```

That value is the PAN + expiry + CVV encrypted by your KMS.

To exit PostgreSQL:

```sql
\q
```

You can also directly run queries without entering the shell:

```bash
docker exec cde-postgres psql -U cde_user -d cde_db -c "SELECT * FROM transactions;"
```
