# triagem-dependabot

Um agente que faz sozinho, toda semana, a triagem das PRs do Dependabot nos repositórios do PET Engenharia de Computação e do IntroComp (Ufes). Ele mescla as atualizações seguras e deixa numa fila só o que precisa de alguém decidir.

Nas quatro semanas de 28/10/2026 a 17/11/2026, ele mesclou 34 PRs em 6 repositórios.

## Como decide

Toda terça às 9h30, o `systemd` roda o [Claude Code](https://docs.anthropic.com/en/docs/claude-code) em modo não interativo com o [`prompt.md`](prompt.md). Uma PR só é mesclada quando tudo isto vale:

- nenhuma dependência sobe de versão major;
- todos os checks passaram no commit atual da PR, e não numa execução anterior ao último rebase;
- cada pacote npm que mudou foi publicado por alguém que já mantinha a versão anterior (ou por GitHub Actions com attestation do repositório certo), sem script de instalação novo e sem dependência de git ou de caminho local;
- a imagem Docker tem uma versão nova de verdade, e não a mesma tag publicada de novo.

Depois do merge, quando o repositório implanta sozinho, o agente acompanha o deploy até o fim. O que ficou aberto vai para `pendencias.md` com o motivo exato: major, CI vermelho ou publicador novo.

## Alertas que não viram PR

Muito alerta do Dependabot nunca vira PR, porque a versão está presa por faixa no `package.json` ou a correção só existe numa major, e fica parado na aba Security. Depois da triagem, o [`alertas.sh`](alertas.sh) lista os alertas critical e high de dependências de produção em todos os repositórios e põe no relatório só os que surgiram desde a semana anterior. Ele roda sem o agente e lê da API só repositório, pacote, gravidade e GHSA; o texto do aviso, escrito por terceiros, fica de fora.

## Por que uma lista fechada de ferramentas

O título, o corpo e as notas de versão de uma PR são escritos por terceiros e podem trazer instruções disfarçadas. Por isso o agente roda com 16 permissões e nada mais: ler PRs e execuções do GitHub Actions, mesclar, comentar `@dependabot rebase`, consultar o registry do npm e o manifesto de imagens Docker, e ler e gravar só na pasta do próprio relatório. Ele não tem `curl`, `npm install`, `git push`, edição de arquivo em repositório nem servidor MCP. Tempo e turnos também têm teto: 90 minutos e 300 turnos.

Só a lista `--allowedTools` não basta: ela aprova de antemão o que está nela, mas o resto ainda segue o modo de permissão e as regras do `settings.json` de quem roda. O script por isso usa `--permission-mode dontAsk` (nega o que não está na lista), `--setting-sources project` (ignora as regras do usuário), `--tools` e `--strict-mcp-config`. Para conferir, peça ao agente um comando fora da lista, como `uname`: ele é negado.

## Regras que vieram de erro

- Logo depois de `@dependabot rebase`, o status de uma PR ainda é o da execução anterior. Uma PR já entrou marcada como falha por isso; agora o check tem de ser do commit atual.
- Uma imagem de terceiros era reconstruída todo dia com a mesma tag, e as versões antigas sumiam em uma semana. Digest fixado nessa imagem quebrava o build com `manifest unknown`. Mesma tag com digest novo agora fica para alguém decidir.
- `gh run list` mistura as execuções do próprio Dependabot com o deploy. Só `--event push` mostra o deploy.

## Instalar

```sh
ln -s "$PWD/triagem.sh" ~/.local/bin/triagem-dependabot
cp systemd/triagem-dependabot.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now triagem-dependabot.timer
```

Precisa do `gh` autenticado com permissão de merge nas organizações, do Claude Code e do `npm`. O relatório e os logs ficam em `~/.local/state/dependencias`.
