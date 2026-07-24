from __future__ import annotations

import logging
import os
import socket
import uuid
from datetime import datetime, timezone
from logging.handlers import SysLogHandler

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request


LOGGER_NAME = "cde.transaction.audit"
SERVICE_NAME = os.getenv("CDE_SERVICE_NAME", "payment-app")
DESTINATION_IP = os.getenv("CDE_SERVICE_IP", "10.100.10.10")
DESTINATION_PORT = os.getenv("CDE_SERVICE_PORT", "8443")


def _build_logger() -> logging.Logger:
    logger = logging.getLogger(LOGGER_NAME)
    if logger.handlers:
        return logger

    logger.setLevel(logging.INFO)
    logger.propagate = False
    server = os.getenv("APP_LOG_SERVER", os.getenv("LOG_SERVER", "10.100.10.200"))
    port = int(os.getenv("APP_LOG_PORT", "514"))

    handler = SysLogHandler(
        address=(server, port),
        facility=SysLogHandler.LOG_LOCAL5,
        socktype=socket.SOCK_DGRAM,
    )
    handler.append_nul = False
    handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(handler)
    return logger


AUDIT_LOGGER = _build_logger()


def _safe_source_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for", "").split(",", 1)[0].strip()
    if forwarded:
        return forwarded.replace(" ", "_")[:64]
    if request.client:
        return request.client.host.replace(" ", "_")[:64]
    return "unknown"


def _emit(*, request: Request, request_id: str, event: str, action: str, result: str, status: int) -> None:
    protocol = request.headers.get("x-forwarded-proto", request.url.scheme).upper()
    message = (
        "CDE_TRANSACTION "
        f"timestamp={datetime.now(timezone.utc).isoformat()} "
        f"event={event} action={action} result={result} status={status} "
        f"request_id={request_id} src_ip={_safe_source_ip(request)} "
        f"dst_ip={DESTINATION_IP} protocol={protocol} dst_port={DESTINATION_PORT} "
        f"service={SERVICE_NAME}"
    )
    AUDIT_LOGGER.info(message)


class CDEAuditMiddleware(BaseHTTPMiddleware):
    """Audit transaction outcomes without reading or logging request/response bodies."""

    async def dispatch(self, request: Request, call_next):
        request_id = uuid.uuid4().hex
        is_transaction = request.method == "POST" and request.url.path == "/process-transaction"

        if is_transaction:
            _emit(
                request=request,
                request_id=request_id,
                event="transaction_created",
                action="CREATE",
                result="STARTED",
                status=0,
            )

        try:
            response = await call_next(request)
        except Exception:
            if is_transaction:
                _emit(
                    request=request,
                    request_id=request_id,
                    event="transaction_processing_error",
                    action="PROCESS",
                    result="ERROR",
                    status=500,
                )
            raise

        response.headers["X-Audit-Request-ID"] = request_id
        status = response.status_code

        if status == 401:
            _emit(
                request=request,
                request_id=request_id,
                event="authentication_failure",
                action="AUTHENTICATE",
                result="FAILURE",
                status=status,
            )
        elif status == 403:
            _emit(
                request=request,
                request_id=request_id,
                event="unauthorized_access_attempt",
                action="AUTHORIZE",
                result="DENIED",
                status=status,
            )
        elif is_transaction and 200 <= status < 300:
            _emit(
                request=request,
                request_id=request_id,
                event="transaction_approved",
                action="APPROVE",
                result="SUCCESS",
                status=status,
            )
        elif is_transaction and status in {400, 402, 409, 422}:
            _emit(
                request=request,
                request_id=request_id,
                event="transaction_declined",
                action="DECLINE",
                result="REJECTED",
                status=status,
            )
        elif is_transaction and status >= 500:
            _emit(
                request=request,
                request_id=request_id,
                event="transaction_processing_error",
                action="PROCESS",
                result="ERROR",
                status=status,
            )

        return response
