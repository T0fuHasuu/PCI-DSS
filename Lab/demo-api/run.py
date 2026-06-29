import uvicorn

uvicorn.run(
    "main:app",
    host="127.0.0.1",
    port=9000,
    log_level="info",
    access_log=False,
)
