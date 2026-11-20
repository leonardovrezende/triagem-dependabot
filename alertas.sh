#!/bin/bash
# Alertas do Dependabot que ninguém olha.
#
# A triagem trata PRs, mas alerta que não vira PR (versão presa por faixa,
# pacote transitivo, correção só em major) fica parado na aba Security. Este
# script conta os alertas graves (critical/high) de dependência de produção em
# todos os repositórios das orgs e acrescenta ao relatório só o que apareceu
# desde a semana anterior. Sem LLM: lê só campos estruturados da API
# (repositório, pacote, gravidade, GHSA), nunca o texto livre do aviso.
#
# Uso: alertas.sh <org> [<org>...]   (escreve em ~/.local/state/dependencias/)
set -uo pipefail

ESTADO="${ESTADO:-$HOME/.local/state/dependencias}"
ANTERIOR="$ESTADO/alertas-anteriores.tsv"
RELATORIO="$ESTADO/pendencias.md"
mkdir -p "$ESTADO"
atual=$(mktemp)
trap 'rm -f "$atual"' EXIT

for org in "$@"; do
  repos=$(gh repo list "$org" --no-archived -L 200 --json name --jq '.[].name') || {
    printf '## Erros\nalertas.sh: não consegui listar os repositórios de %s.\n' "$org" >>"$RELATORIO"
    exit 1
  }
  for repo in $repos; do
    gh api --paginate "repos/$org/$repo/dependabot/alerts?state=open&per_page=100" --jq '.[]
      | select(.dependency.scope == "runtime")
      | select(.security_advisory.severity == "critical" or .security_advisory.severity == "high")
      | [.number, .security_advisory.severity, .dependency.package.name,
         .security_advisory.ghsa_id, .dependency.manifest_path] | @tsv' 2>/dev/null |
      sed "s#^#$org/$repo\t#" >>"$atual"
  done
done
sort -o "$atual" "$atual"

if [ ! -s "$ANTERIOR" ]; then
  # Primeira execução: o acervo inteiro vai uma vez só, resumido por repositório.
  novos="$atual"
  titulo="## Alertas graves de produção em aberto (primeira contagem)"
else
  novos=$(mktemp)
  trap 'rm -f "$atual" "$novos"' EXIT
  # Novo = repositório e número de alerta que não estavam na lista anterior.
  awk -F'\t' 'NR == FNR {visto[$1, $2] = 1; next} !(($1, $2) in visto)' "$ANTERIOR" "$atual" >"$novos"
  titulo="## Alertas graves de produção novos desde a semana passada"
fi

if [ -s "$novos" ]; then
  {
    echo "$titulo"
    awk -F'\t' '{n[$1]++; if ($3=="critical") c[$1]++; if (!(($1, $4) in p)) {p[$1, $4]=1; k[$1]++}}
      END {for (r in n) printf "- %s: %d (%d críticos) em %d pacotes\n", r, n[r], c[r]+0, k[r]}' "$novos" | sort
    if [ "$novos" != "$atual" ]; then
      echo
      awk -F'\t' '{printf "- %s: %s %s (%s, %s)\n", $1, $4, $3, $5, $6}' "$novos"
    fi
    total=$(wc -l <"$atual")
    echo
    echo "Total em aberto agora: $total. Antes de chamar de grave, conferir se o pacote vai mesmo para a imagem final (skill dependencias, \"Alertas do Dependabot\")."
  } >>"$RELATORIO"
fi

cp "$atual" "$ANTERIOR"
