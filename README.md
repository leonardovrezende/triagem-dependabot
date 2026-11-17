# triagem-dependabot

Um agente que faz sozinho, toda semana, a triagem das PRs do Dependabot nos repositórios do PET Engenharia de Computação e do IntroComp (Ufes). Ele mescla as atualizações seguras e deixa numa fila só o que precisa de alguém decidir.

Da primeira rodada, em 28/10/2026, até 17/11/2026 foram 4 execuções e 34 PRs mescladas em 6 repositórios.

## Como decide

Toda terça às 9h30, o `systemd` roda o [Claude Code](https://docs.anthropic.com/en/docs/claude-code) em modo não interativo com o [`prompt.md`](prompt.md). Uma PR só é mesclada quando tudo isto vale:

- nenhuma dependência sobe de versão major;
- todos os checks passaram no commit atual da PR, e não numa execução anterior ao último rebase;
- cada pacote npm que mudou foi publicado por alguém que já mantinha a versão anterior (ou por GitHub Actions com attestation do repositório certo), sem script de instalação novo e sem dependência de git ou de caminho local;
- a imagem Docker tem uma versão nova de verdade, e não a mesma tag publicada de novo.

Depois do merge, quando o repositório implanta sozinho, o agente acompanha o deploy até o fim. O que ficou aberto vai para `pendencias.md` com o motivo exato: major, CI vermelho ou publicador novo.

## Por que uma lista fechada de ferramentas

O título, o corpo e as notas de versão de uma PR são escritos por terceiros e podem trazer instruções disfarçadas. Por isso o agente roda com 15 ferramentas permitidas e nada mais: ler PRs e execuções do GitHub Actions, mesclar, comentar `@dependabot rebase`, consultar o registry do npm e o manifesto de imagens Docker. Ele não tem `curl`, `npm install`, `git push`, edição de arquivo em repositório nem leitura do resto do disco. Tempo e turnos também têm teto: 90 minutos e 300 turnos.

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

Precisa do `gh` autenticado com permissão de merge nas organizações, do Claude Code e do `npm`. O estado e os logs ficam em `~/.local/state/dependencias` (ou em `$TRIAGEM_ESTADO`).
