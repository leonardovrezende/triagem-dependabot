#!/bin/bash
# Triagem semanal das PRs do Dependabot, sem ninguém olhando.
#
# Roda o Claude Code em modo não interativo com o prompt.md ao lado deste
# arquivo. O texto das PRs (notas de versão, changelog) vem de terceiros e
# pode trazer instrução embutida, por isso o agente recebe uma lista fechada
# de ferramentas: lê PRs e execuções, mescla, comenta e consulta o registry.
# Não tem curl, npm install, push, edição em repositório nem leitura do home.
set -uo pipefail

AQUI="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ESTADO="$HOME/.local/state/dependencias"
CLAUDE="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
mkdir -p "$ESTADO"
LOG="$ESTADO/execucao-$(date +%Y%m%d-%H%M).log"
cd "$ESTADO" || exit 1

# O npm vem do nvm, que o systemd não carrega. Pelo alias default, para não
# quebrar quando o nvm trocar de versão.
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  . "$HOME/.nvm/nvm.sh" && nvm use --silent default
fi

ferramentas=(
  "Read(~/.local/state/dependencias/**)" "Edit(~/.local/state/dependencias/**)"
  "Write(~/.local/state/dependencias/**)"
  "Bash(gh search prs:*)" "Bash(gh pr list:*)" "Bash(gh pr view:*)" "Bash(gh pr diff:*)"
  "Bash(gh pr checks:*)" "Bash(gh pr merge:*)" "Bash(gh pr comment:*)"
  "Bash(gh run list:*)" "Bash(gh run view:*)" "Bash(gh run watch:*)" "Bash(gh repo view:*)"
  "Bash(npm view:*)" "Bash(docker buildx imagetools inspect:*)"
)

# A lista só restringe de verdade com as quatro opções abaixo. Sem elas, o
# --allowedTools apenas aprova de antemão, e o resto segue o modo de permissão
# e as regras do settings.json do usuário (onde pode haver curl liberado):
#   --permission-mode dontAsk  nega o que não está na lista, em vez de perguntar;
#   --setting-sources project  ignora o settings.json do usuário (regras e hooks);
#   --tools                    só estas ferramentas existem para o agente;
#   --strict-mcp-config        nenhum servidor MCP do usuário.
timeout 90m "$CLAUDE" -p "$(cat "$AQUI/prompt.md")" \
  --permission-mode dontAsk --setting-sources project \
  --tools Bash,Read,Edit,Write --strict-mcp-config \
  --allowedTools "${ferramentas[@]}" --max-turns 300 >"$LOG" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  { echo "## Erros"; echo "A triagem saiu com código $rc em $(date '+%d/%m/%Y %H:%M'). Log: \`$LOG\`."; } >>"$ESTADO/pendencias.md"
fi

# Guarda só os 8 logs mais recentes.
ls -1t "$ESTADO"/execucao-*.log 2>/dev/null | tail -n +9 | xargs -r rm -f
exit 0
