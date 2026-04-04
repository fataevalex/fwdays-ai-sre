# Лабораторна №2

## Мета
Розгорнути на власному self managed кластері  kagent, agentgateway, підключити модель та створити declarative MCP tool server і агента.

## Виконано
- Розгорнуто kagent та agentgateway за допомогою GitOps через Argocd
- Отримано доступ до UI:
    - kagent UI
    - agentgateway UI
- Підключено модель через `default-model-config`
- Використано `RemoteMCPServer` `homeassistant`, що окремо був увімкнений на домашньому homeassistant сервері
- Створено та перевірено declarative агента `ha-agent`
- Агент успішно виконує MCP tool calls та повертає реальні дані з Home Assistant
- Додатково налаштована OIDC аутентифікація через keycloak за допомогою oauth2-proxy

## Використані ресурси
- ModelConfig: `default-model-config`
- RemoteMCPServer: `homeassistant`
- Agent: `ha-agent`

## Артефакти
- [yaml маніфести](artifacts/cluster/)
- [screenshots](artifacts/screenshots/)
- [![asciicast](https://asciinema.org/a/tQqmMixhn0WnfOKS.svg)](https://asciinema.org/a/tQqmMixhn0WnfOKS)


## Результат
Агент у kagent UI успішно відповідає на запити, використовуючи MCP tool виклик до Home Assistant.