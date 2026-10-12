#!/usr/bin/env python3
"""Stub HTTP da API Chatvolt — usado por `tests/smoke.sh --stub`.

Reproduz as formas de resposta REAIS verificadas em 2026-10-12 (ver SOURCES.md):
objetos na raiz, arrays na raiz e envelope `{data, pagination}` só nas listagens.
Também injeta os cenários de erro que os scripts precisam tratar:
401 (key inválida), 402 (quota), 429 (rate limit com retry) e 404.

Uso: python3 tests/stub_server.py [porta]   (porta 0 = escolhe uma livre e imprime)
"""

import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

STUB_KEY = "stub-key"
_flaky_hits = {"n": 0}

AGENT = {
    "id": "agent-1",
    "name": "Agente Stub",
    "handle": "stub",
    "description": "agente de teste offline",
    "modelName": "gpt_54_nano",
    "temperature": 0.3,
    "visibility": "private",
    "systemPrompt": "Você é um agente de teste. Responda sempre em português.",
}

TOOLS = [
    {
        "id": "tool-1",
        "type": "http",
        "agentId": "agent-1",
        "datastoreId": None,
        "formId": None,
        "isRaw": False,
        "notifyOnFailure": False,
        "serviceProviderId": None,
        "createdAt": "2026-10-01T13:06:13.371Z",
        "updatedAt": "2026-10-06T15:35:31.965Z",
        "config": {
            "name": "consultar_status",
            "description": "Consulta o status de um pedido.",
            "url": "https://exemplo.test/pedidos/:pedido_id",
            "method": "GET",
            "withApproval": False,
            "headers": [],
            "body": [],
            "queryParameters": [],
            "pathVariables": [{"key": "pedido_id", "value": "", "isUserProvided": True}],
            "hasMaximumToolCalls": True,
            "maximumToolCalls": 1,
            "isErrorCountable": True,
        },
    },
    {
        "id": "tool-2",
        "type": "datastore",
        "agentId": "agent-1",
        "datastoreId": "ds-1",
        "formId": None,
        "isRaw": False,
        "serviceProviderId": None,
        "config": {},
    },
]

CONVERSATIONS = [
    {
        "id": "conv-api-1",
        "title": None,
        "unreadMessagesCount": 0,
        "isAiEnabled": True,
        "channel": "api",
        "status": "UNRESOLVED",
        "priority": "MEDIUM",
        "agentId": "agent-1",
        "organizationId": "org-stub",
        "createdAt": "2026-10-10T12:00:00.000Z",
        "updatedAt": "2026-10-10T12:05:00.000Z",
        "participantsContacts": [{"id": "c-1", "firstName": "Teste", "phoneNumber": "5511900000000"}],
    },
    {
        "id": "conv-wa-1",
        "title": "Atendimento WhatsApp",
        "unreadMessagesCount": 3,
        "isAiEnabled": True,
        "channel": "whatsapp",
        "status": "HUMAN_REQUESTED",
        "priority": "HIGH",
        "agentId": "agent-1",
        "organizationId": "org-stub",
        "createdAt": "2026-10-11T09:00:00.000Z",
        "updatedAt": "2026-10-11T09:10:00.000Z",
        "participantsContacts": [{"id": "c-2", "firstName": "Cliente", "phoneNumber": "5511911111111"}],
    },
]

MESSAGES = {
    "conv-api-1": [
        {"id": "m-1", "from": "human", "text": "Bom dia", "createdAt": "2026-10-10T12:00:00.000Z"},
        {"id": "m-2", "from": "agent", "text": "Bom dia! Como posso ajudar?", "createdAt": "2026-10-10T12:00:02.000Z"},
    ],
    "conv-wa-1": [
        {"id": "m-3", "from": "human", "text": "Quero falar com um atendente", "createdAt": "2026-10-11T09:00:00.000Z"},
        {"id": "m-4", "from": "agent", "text": "Vou transferir você.", "createdAt": "2026-10-11T09:00:05.000Z"},
    ],
}

DATASTORES = [
    {
        "id": "ds-1",
        "name": "Base Stub",
        "description": "base de conhecimento de teste",
        "type": "qdrant",
        "autosync": True,
        "visibility": "private",
        "createdAt": "2026-10-01T10:00:00.000Z",
        "updatedAt": "2026-10-02T10:00:00.000Z",
        "_count": {"datasources": 2},
    }
]

SOURCES = [
    {
        "id": "src-1",
        "type": "file",
        "name": "politica.md",
        "status": "synched",
        "config": {"tags": ["politica", "faq"], "custom_id": "tenant-1", "mime_type": "text/markdown"},
        "datastoreId": "ds-1",
        "nbChunks": 3,
        "textSize": 420,
        "nbTokens": 110,
        "lastSynch": "2026-10-02T10:00:00.000Z",
    },
    {
        "id": "src-2",
        "type": "qa",
        "name": "horario-de-funcionamento",
        "status": "synched",
        "config": {"tags": ["faq"], "custom_id": "tenant-1"},
        "datastoreId": "ds-1",
        "nbChunks": 1,
        "textSize": 90,
        "nbTokens": 24,
        "lastSynch": "2026-10-02T10:01:00.000Z",
    },
]

MODELS = [
    {"model_name": "gpt_54_nano", "model_description": "OpenAI: GPT-5.4 Nano", "hasVision": True, "isToolCallingSupported": True},
    {"model_name": "claude_sonnet_5", "model_description": "Anthropic: Claude Sonnet 5", "hasVision": True, "isToolCallingSupported": True},
]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):  # silencia o log padrão
        pass

    # ── infraestrutura ────────────────────────────────────────────────
    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        if not raw:
            return {}
        try:
            return json.loads(raw)
        except Exception:
            return {"_raw": raw.decode("utf-8", "replace")}

    def _send(self, status, payload, *, raw_text=None):
        if raw_text is not None:
            body = raw_text.encode()
            ctype = "text/plain; charset=utf-8"
        else:
            body = json.dumps(payload, ensure_ascii=False).encode()
            ctype = "application/json; charset=utf-8"
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        header = self.headers.get("Authorization") or ""
        return header == f"Bearer {STUB_KEY}"

    def _path_query(self):
        u = urlparse(self.path)
        return u.path, {k: v[-1] for k, v in parse_qs(u.query).items()}

    # ── rotas ─────────────────────────────────────────────────────────
    def do_GET(self):
        path, qs = self._path_query()

        if path == "/flaky-tools":
            _flaky_hits["n"] += 1
            if _flaky_hits["n"] <= 2:
                self.send_response(429)
                body = json.dumps({"error": "RATE_LIMIT_EXCEEDED"}).encode()
                self.send_header("Content-Type", "application/json")
                self.send_header("Retry-After", "1")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            self._send(200, TOOLS)
            return

        if path == "/quota-me":
            self._send(402, {"data": None, "success": False, "error": {"message": "Limite de uso mensal atingido.", "code": "QUOTA_EXCEEDED"}})
            return

        if not self._authorized():
            self._send(403, {"error": "Forbidden"})
            return

        if path == "/agents/models":
            self._send(200, MODELS)
        elif path == "/agents":
            self._send(200, [AGENT])
        elif re.fullmatch(r"/agents/[^/]+/tools", path):
            self._send(200, TOOLS)
        elif re.fullmatch(r"/agents/[^/]+/tools/[^/]+", path):
            self._send(404, {"error": "not found"})  # contrato real: não existe
        elif re.fullmatch(r"/agents/[^/]+", path):
            if path == f"/agents/{AGENT['id']}" or path == "/agents/flaky":
                self._send(200, dict(AGENT, id=path.rsplit("/", 1)[-1]))
            else:
                self._send(404, {"error": "NOT_FOUND"})
        elif path == "/conversation":
            limit = int(qs.get("limit") or 25)
            self._send(200, CONVERSATIONS[:limit])
        elif re.fullmatch(r"/conversation/[^/]+/messages/\d+", path):
            conv_id = path.split("/")[2]
            count = int(path.rsplit("/", 1)[-1])
            if conv_id not in MESSAGES:
                self._send(404, {"error": "NOT_FOUND"})
            else:
                self._send(
                    200,
                    {
                        "status": "UNRESOLVED",
                        "isAiEnabled": True,
                        "userId": None,
                        "organizationId": "org-stub",
                        "messages": MESSAGES[conv_id][-count:],
                    },
                )
        elif re.fullmatch(r"/conversation/[^/]+", path):
            conv_id = path.rsplit("/", 1)[-1]
            found = next((c for c in CONVERSATIONS if c["id"] == conv_id), None)
            self._send(200, found) if found else self._send(404, {"error": "NOT_FOUND"})
        elif path == "/datastores/list":
            self._send(200, {"data": DATASTORES, "pagination": {"total": len(DATASTORES), "offset": 0, "limit": 20, "count": len(DATASTORES)}})
        elif path == "/datasources/list":
            if not qs.get("datastoreId"):
                self._send(400, {"error": "datastoreId is required and must be a single string"})
                return
            items = [s for s in SOURCES if s["datastoreId"] == qs["datastoreId"]]
            self._send(200, {"data": items, "pagination": {"total": len(items), "offset": int(qs.get("offset") or 0), "limit": int(qs.get("limit") or 20), "count": len(items)}})
        elif re.fullmatch(r"/datasources/[^/]+", path):
            if not qs.get("idstore"):
                self._send(400, {"error": "idstore is required"})
                return
            src = next((s for s in SOURCES if s["id"] == path.rsplit("/", 1)[-1]), None)
            self._send(200, src) if src else self._send(404, {"error": "NOT_FOUND"})
        elif re.fullmatch(r"/datastores/[^/]+", path):
            ds = next((d for d in DATASTORES if d["id"] == path.rsplit("/", 1)[-1]), None)
            self._send(200, ds) if ds else self._send(404, {"error": "NOT_FOUND"})
        else:
            self._send(404, {"error": "NOT_FOUND"})

    def do_POST(self):
        path, qs = self._path_query()
        body = self._body()

        if path == "/datastores/quota-me/query":
            self._send(402, {"error": {"message": "Limite de uso mensal atingido.", "code": "QUOTA_EXCEEDED"}})
            return
        if not self._authorized():
            self._send(403, {"error": "Forbidden"})
            return

        if re.fullmatch(r"/agents/[^/]+/query", path):
            self._send(200, {"answer": "PONG-STUB", "sources": [], "messageId": "m-9", "conversationId": "conv-nova-1", "visitorId": "v-1"})
        elif re.fullmatch(r"/agents/[^/]+/tools", path):
            tool = dict(body) if isinstance(body, dict) else {}
            tool.setdefault("id", "tool-nova-1")
            self._send(201, tool)
        elif path == "/datasources":
            if not isinstance(body, dict) or "datastoreId" not in body:
                self._send(400, {"error": "INVALID_REQUEST"})
                return
            existing = next((s for s in SOURCES if s["id"] == body.get("id")), None) if body.get("id") else None
            if body.get("id") and not existing:
                self._send(404, {"error": "NOT_FOUND"})
                return
            if body.get("id") and not body.get("isUpdateText") and body.get("datasourceText"):
                self._send(400, {"error": "INVALID_REQUEST"})
                return
            if existing:
                # upsert: substitui o config (não mescla) e preserva o conteúdo indexado
                existing["config"] = dict(body.get("config") or {})
                existing["name"] = body.get("name") or existing["name"]
                existing["nbSynch"] = (existing.get("nbSynch") or 0) + 1
                existing["status"] = "synched"
                self._send(200, existing)
                return
            src = {
                "id": body.get("id") or f"src-nova-{len(SOURCES) + 1}",
                "type": body.get("type", "file"),
                "name": body.get("name", "nova-fonte"),
                "status": "synched",
                "config": {**(body.get("config") or {})},
                "datastoreId": body["datastoreId"],
                "nbChunks": 2,
                "nbSynch": 1,
                "textSize": len(body.get("datasourceText") or ""),
            }
            SOURCES.append(src)
            self._send(200, src)
        elif path == "/datastores":
            self._send(200, {"id": "ds-nova-1", "name": body.get("name", "Base nova"), "type": "qdrant", "description": body.get("description")})
        elif path == "/datastores/ds-1/query" or re.fullmatch(r"/datastores/[^/]+/query", path):
            filters = (body or {}).get("filters") or {}
            if filters.get("custom_ids") and filters["custom_ids"] != ["tenant-1"]:
                self._send(200, [])
                return
            self._send(200, [{"text": "A política de devolução permite troca em 30 dias.", "score": 0.72, "datasource_name": "politica.md", "datasource_id": "src-1", "custom_id": "tenant-1", "offset": 0}])
        else:
            self._send(404, {"error": "NOT_FOUND"})

    def do_PATCH(self):
        path, qs = self._path_query()
        body = self._body()
        if not self._authorized():
            self._send(403, {"error": "Forbidden"})
            return
        if re.fullmatch(r"/agents/[^/]+", path):
            self._send(200, {**AGENT, **body})
        elif re.fullmatch(r"/agents/[^/]+/webhook", path):
            if "type" not in qs or "enabled" not in qs:
                self._send(400, {"error": 'The parameters "id", "service-provider-type", and "enabled" are required.'})
                return
            self._send(200, None, raw_text=f"{qs['type']} webhook {'enabled' if qs['enabled'] == 'true' else 'disabled'}")
        elif re.fullmatch(r"/datastores/[^/]+", path):
            self._send(200, {**DATASTORES[0], **(body or {})})
        elif re.fullmatch(r"/agents/[^/]+/tools/[^/]+", path):
            tool = next((t for t in TOOLS if t["id"] == path.rsplit("/", 1)[-1]), None)
            self._send(200, tool) if tool else self._send(404, {"error": "NOT_FOUND"})
        else:
            self._send(404, {"error": "NOT_FOUND"})

    def do_DELETE(self):
        path, _ = self._path_query()
        if not self._authorized():
            self._send(403, {"error": "Forbidden"})
            return
        if re.fullmatch(r"/conversation/[^/]+", path):
            conv_id = path.rsplit("/", 1)[-1]
            channel = next((c["channel"] for c in CONVERSATIONS if c["id"] == conv_id), "api")
            self._send(200, {"success": True, "message": "Conversation deleted.", "conversationId": conv_id, "channel": channel})
        elif re.fullmatch(r"/datasources/[^/]+", path):
            sid = path.rsplit("/", 1)[-1]
            src = next((s for s in SOURCES if s["id"] == sid), None)
            if src:
                SOURCES.remove(src)
                self._send(200, src)
            else:
                self._send(404, {"error": "NOT_FOUND"})
        elif re.fullmatch(r"/datastores/[^/]+", path):
            self._send(200, DATASTORES[0])
        elif re.fullmatch(r"/agents/[^/]+/tools/[^/]+", path):
            self._send(200, {"success": True})
        else:
            self._send(404, {"error": "NOT_FOUND"})


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    server = HTTPServer(("127.0.0.1", port), Handler)
    print(server.server_address[1], flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
