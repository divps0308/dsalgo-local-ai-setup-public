param([switch]$OpenBrowser)
docker compose -f "$PSScriptRoot\docker-compose.yml" up -d --build agent-studio local-agent-gateway
if($OpenBrowser){Start-Process 'http://localhost:3001'}
