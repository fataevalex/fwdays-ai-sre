# Лабораторна №4 — A2A Agent

## Мета
Ознайомитися зі специфікацією A2A, реалізувати власного агента з Agent Card та отримати карту агента за Well-Known URI.

## Реалізація
Було створено власного агента `smart-home-a2a-agent` у директорії `ha-agent/`.

Агент реалізовано як HTTP сервіс на FastAPI з такими endpoint:
- `GET /.well-known/agent.json`
- `GET /.well-known/agent-card.json`
- `POST /task`

Агент інтегрується з реальним Home Assistant MCP server через Streamable HTTP transport.

## Можливості агента
Агент підтримує дві основні дії:
- `list_tools` — отримання списку доступних MCP tools
- `call_tool` — виклик конкретного MCP tool з аргументами

## Agent Card
Agent Card успішно доступна через Well-Known URI:

- `/.well-known/agent.json`
- `/.well-known/agent-card.json`

## Результат
Було підтверджено, що агент:
- успішно повертає Agent Card
- отримує список доступних tools з Home Assistant MCP
- виконує реальний виклик MCP tool
- білд артефакта робиться через github actions та за допомогою helm чарта деплоїться в реальний кластер

## Приклад використання
Було виконано виклик:

- `action: call_tool`
- `tool_name: GetLiveContext`

У відповідь агент повернув актуальний live context з Home Assistant, включаючи реальні значення сенсорів.

Це також дозволило повторити сценарій з Lab 2 через власного A2A агента.

## Перевірка Agent Card
```bash
curl -s http://localhost:8080/.well-known/agent.json | jq
```
відповідь
```text
{
  "name": "smart-home-a2a-agent",
  "description": "A2A agent that connects to a real Home Assistant MCP server.",
  "version": "1.0.0",
  "provider": {
    "organization": "fataevalex",
    "url": "https://github.com/fataevalex/fwdays-ai-sre"
  },
  "url": "https://ha-agent.local",
  "capabilities": {
    "streaming": false,
    "pushNotifications": false
  },
  "authentication": {
    "schemes": [
      {
        "type": "none"
      }
    ]
  },
  "skills": [
    {
      "id": "list-homeassistant-tools",
      "name": "List Home Assistant MCP tools",
      "description": "Returns tools exposed by the Home Assistant MCP server.",
      "inputModes": [
        "application/json"
      ],
      "outputModes": [
        "application/json"
      ]
    },
    {
      "id": "call-homeassistant-tool",
      "name": "Call Home Assistant MCP tool",
      "description": "Calls one Home Assistant MCP tool with arguments.",
      "inputModes": [
        "application/json"
      ],
      "outputModes": [
        "application/json"
      ]
    }
  ]
}

```

## Перевірка списку MCP tools
```bash
curl -s -X POST http://localhost:8080/task \
  -H "Content-Type: application/json" \
  -d '{"action":"list_tools"}' | jq
```
відповідь
```text
{
  "action": "list_tools",
  "mcp_url": "http://homeassistant.local:8123/api/mcp",
  "tools": [
    ....
    {
      "name": "HassTurnOff",
      "description": "Turns off/closes a device or entity. For locks, this performs an 'unlock' action. Use for requests like 'turn off', 'deactivate', 'disable', or 'unlock'.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "name": {
            "type": "string"
          },
          "area": {
            "type": "string"
          },
          "floor": {
            "type": "string"
          },
          "domain": {
            "type": "array",
            "items": {
              "type": "string"
            }
          },
          "device_class": {
            "type": "array",
            "items": {
              "type": "string",
              "enum": [
                "awning",
                "blind",
                "curtain",
                "damper",
                "door",
                "garage",
                "gate",
                "shade",
                "shutter",
                "window",
                "identify",
                "restart",
                "update",
                "water",
                "gas",
                "outlet",
                "switch",
                "tv",
                "speaker",
                "receiver"
              ]
            }
          }
        }
      }
    },
    ...
  ]
}

```
## Приклад запит значення з датчика
```bash
curl -s -X POST http://localhost:8080/task \
  -H "Content-Type: application/json" \
  -d '{"action":"call_tool","tool_name":"GetLiveContext","arguments":{}}' \
| jq -r '.result[0] | fromjson | .result' \
| grep -A2 "Балкон Температура" \
| grep state \
| sed -E "s/.*'([^']+)'.*/\1/"

```
відповідь
```text
26.4
```


## Висновок
Було реалізовано власного A2A агента з Agent Card та підтримкою Well-Known URI. Агент інтегровано з реальним MCP сервером Home Assistant, що підтверджує його працездатність у реальному середовищі.