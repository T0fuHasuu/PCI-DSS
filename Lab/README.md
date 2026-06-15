# Network Segmentation Effectiveness for PCI DSS Scope Reduction : **T0fuHasuu**

### **Content :**

### 1. [Quick Start](#quick-start-guide)
### 2. [Data Privacy](#data-privacy)

## Directory Structure
```
LAB/
├── app/                  
│   ├── __init__.py
│   └── app.py           
├── db/                   
│   ├── __init__.py
│   └── init_db.sql       
├── kms/                  
│   ├── __init__.py
│   └── main.py
├── Markdown/             
│   ├── NETWORK.md      
│   └── QUICK.md         
├── S2/...                
├── .env.example         
├── .gitignore            
├── docker-compose.yml    
├── Dockerfile           
├── README.md             
├── requirements.txt      
└── test.sh               
```

## Quick Start

### One-Step Deployment

```bash
docker-compose up -d && sleep 30
```

### Ensure Services Running
```bash
chmod +x test.sh && ./test.sh
```

## Data Privacy

✓ PAN is masked (only last 4 digits in plain text)

✓ CVV is never stored

✓ Card data is encrypted before storage

✓ Only tokenized references in transaction logs