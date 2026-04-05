import os
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client

APP_NAME = "smart-home-a2a-agent"
APP_VERSION = "1.0.0"

MCP_URL = os.getenv("HA_MCP_URL", "http://homeassistant.local:8123/api/mcp")
HA_TOKEN = os.getenv("HA_TOKEN", "")
AGENT_URL = os.getenv("AGENT_URL", "https://ha-agent.local")

app = FastAPI(title=APP_NAME, version=APP_VERSION)


class BearerAuth(httpx.Auth):
    def __init__(self, token: str):
        self.token = token

    def auth_flow(self, request):
        request.headers["Authorization"] = f"Bearer {self.token}"
        yield request


async def open_mcp_session() -> tuple[Any, Any, Any, ClientSession]:
    auth = BearerAuth(HA_TOKEN) if HA_TOKEN else None

    http_client = httpx.AsyncClient(
        auth=auth,
        follow_redirects=True,
        timeout=60.0,
    )

    transport_cm = streamable_http_client(
        url=MCP_URL,
        http_client=http_client,
    )
    read_stream, write_stream, _ = await transport_cm.__aenter__()

    session_cm = ClientSession(read_stream, write_stream)
    session = await session_cm.__aenter__()
    await session.initialize()

    return transport_cm, session_cm, http_client, session


async def close_mcp_session(transport_cm: Any, session_cm: Any, http_client: Any) -> None:
    await session_cm.__aexit__(None, None, None)
    await transport_cm.__aexit__(None, None, None)
    await http_client.aclose()

def build_agent_card() -> dict[str, Any]:
    return {
        "name": APP_NAME,
        "description": "A2A agent that connects to a real Home Assistant MCP server.",
        "version": APP_VERSION,
        "provider": {
            "organization": "fataevalex",
            "url": "https://github.com/fataevalex/fwdays-ai-sre",
        },
        "url": AGENT_URL,
        "capabilities": {
            "streaming": False,
            "pushNotifications": False,
        },
        "authentication": {
            "schemes": [{"type": "none"}]
        },
        "skills": [
            {
                "id": "list-homeassistant-tools",
                "name": "List Home Assistant MCP tools",
                "description": "Returns tools exposed by the Home Assistant MCP server.",
                "inputModes": ["application/json"],
                "outputModes": ["application/json"],
            },
            {
                "id": "call-homeassistant-tool",
                "name": "Call Home Assistant MCP tool",
                "description": "Calls one Home Assistant MCP tool with arguments.",
                "inputModes": ["application/json"],
                "outputModes": ["application/json"],
            },
        ],
    }


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/.well-known/agent.json")
def agent_json() -> dict[str, Any]:
    return build_agent_card()


@app.get("/.well-known/agent-card.json")
def agent_card_json() -> dict[str, Any]:
    return build_agent_card()


class TaskRequest(BaseModel):
    action: str = Field(description="list_tools or call_tool")
    tool_name: str | None = None
    arguments: dict[str, Any] = Field(default_factory=dict)


@app.post("/task")
async def run_task(task: TaskRequest) -> dict[str, Any]:
    transport_cm = None
    session_cm = None
    http_client = None

    try:
        transport_cm, session_cm, http_client, session = await open_mcp_session()

        if task.action == "list_tools":
            tools_result = await session.list_tools()
            return {
                "action": "list_tools",
                "mcp_url": MCP_URL,
                "tools": [
                    {
                        "name": tool.name,
                        "description": tool.description,
                        "inputSchema": tool.inputSchema,
                    }
                    for tool in tools_result.tools
                ],
            }

        if task.action == "call_tool":
            if not task.tool_name:
                raise HTTPException(
                    status_code=400,
                    detail="tool_name is required for action=call_tool",
                )

            result = await session.call_tool(task.tool_name, task.arguments)
            content: list[str] = []

            for item in result.content:
                text = getattr(item, "text", None)
                content.append(text if text is not None else str(item))

            return {
                "action": "call_tool",
                "tool_name": task.tool_name,
                "arguments": task.arguments,
                "result": content,
                "isError": getattr(result, "isError", False),
            }

        raise HTTPException(
            status_code=400,
            detail="Unsupported action. Use list_tools or call_tool.",
        )

    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    finally:
        if transport_cm is not None and session_cm is not None and http_client is not None:
            await close_mcp_session(transport_cm, session_cm, http_client)