# Bom Dia, Artisan — widget para o DankMaterialShell

O resumo diário do ecossistema Laravel, de [bom-dia-artisan.dev](https://bom-dia-artisan.dev/),
dentro da barra do DMS.

Este é um port do [omarchy-bom-dia-artisan](https://github.com/mmonari/omarchy-bom-dia-artisan),
de m0u (MIT), que foi escrito para o `omarchy-shell`. A lógica (busca, decisões, Markdown,
filtros, marcas de lida) é a mesma; a interface e a I/O foram reescritas para a API de plugins
do DMS.

> Não oficial. Não é afiliado ao bom-dia-artisan.dev. Lê a API pública `/api/reports` uma vez por dia.

- **Uma caneca na barra.** Ela fica quieta até sair uma edição nova. Aí aparece vapor e um ponto
  vermelho. Com mais de uma edição não lida, o ponto mostra a contagem.
- **A edição inteira no painel.** Resumo dos editores, a nota "lançado × só mesclado", e todos os
  itens agrupados por pacote, com chip de status, repositório, a linha "por que importa" e a nota
  completa sob demanda.
- **Os últimos 16 dias** a uma seta de distância. Uma edição conta como lida depois de ficar na tela
  por um instante.
- **Uma verificação por dia**, às 09:30 por padrão. Se a edição ainda não saiu, pergunta de hora em
  hora só se ela já saiu, e não baixa a lista inteira.
- **Respeita a API.** Fica bem abaixo do limite de 10 requisições por minuto e espera o `Retry-After`
  quando recebe `429`.
- **Funciona sem rede.** A última resposta fica em cache, e o rodapé diz quando você está vendo a cópia salva.

## Instalação

Pré-requisitos: `curl`, `xdg-open` e o CLI `dms` (já vêm com o DMS e com o Omarchy).

```bash
ln -s ~/Projects/Omarchy/Plugins/dms-bom-dia-artisan ~/.config/DankMaterialShell/plugins/bomDiaArtisan
```

Depois:

1. Reinicie o DMS: `systemctl --user restart dms`.
2. Em **Configurações → Plugins**, clique em **Scan for Plugins** e ative o *Bom Dia, Artisan*.
3. Adicione o widget a uma seção da barra (**Configurações → DankBar → Widgets**). O id é `bomDiaArtisan`.

## Configurações

Em **Configurações → Plugins → Bom Dia, Artisan**:

| Opção | Padrão | Significado |
|-------|--------|-------------|
| Verificar às | `09:30` | Horário local (HH:MM) da verificação diária. A data da edição segue o fuso de São Paulo. |
| Aviso para cada nova edição | ligado | Um aviso por edição nova. Não abre o painel ao clicar: o `dms notify` não tem ação de clique. |

## Teclas (com o painel aberto)

| Tecla | Faz |
|-------|-----|
| `↑` `↓` / `j` `k` | Move entre os itens |
| `Espaço` | Lê a nota completa do item (de novo para recolher) |
| `Enter` | Abre a fonte do item (release ou PR no GitHub); sem item selecionado, abre a edição no site |
| `←` `→` / `h` `l` | Dia anterior / próximo |
| `f` / `F`, `1`–`4` | Alterna / escolhe o filtro (Tudo, Releases, Merged, Dicas) |
| `n` | Vai para a próxima edição não lida |
| `o` | Abre esta edição no site |
| `m` | Marca todas as edições como lidas |
| `r` | Busca agora |
| `g` `G` / `Home` `End` | Primeiro / último item |
| `Esc` | Fecha o painel (o próprio DMS trata a tecla) |

Com o mouse: clique na caneca para abrir o painel. Clique no título para abrir a edição no site, em ↻
para buscar agora, numa linha para ler a nota e no ↗ para abrir a fonte.

## Onde ficam os dados

| O quê | Onde |
|-------|------|
| Marcas de lida e última edição avisada | `~/.local/state/bom-dia-artisan/state.json` |
| Resposta da API em cache | `~/.cache/bom-dia-artisan/reports.json` |
| Fonte dos dados | `https://bom-dia-artisan.dev/api/reports` (16 edições) |
| Sondagem do fim do dia | `https://bom-dia-artisan.dev/api/reports/<AAAA-MM-DD>`, uma edição, `404` até sair. Nunca é cacheada |
| Ativação do plugin | `~/.config/DankMaterialShell/plugin_settings.json` (chave `enabled`) |

Apagar `state.json` faz o plugin tratar a próxima execução como a primeira: só a edição mais nova
fica não lida.

---

## Desenvolvimento

O plugin tem duas partes:

- **Lógica em JavaScript puro** (`Model.js`, `Source.js`, `Actions.js`, `Glyphs.js`): sem QML e sem
  I/O. Os testes em `test/` carregam os mesmos arquivos que o DMS carrega.
- **Interface e I/O em QML**:
  - `BomDiaDaemon.qml` é o único que busca, grava o cache, marca as lidas e avisa. Como é um daemon,
    roda uma vez só, mesmo com a barra em vários monitores.
  - `BomDiaWidget.qml` é a caneca na barra. `BomDiaPanel.qml` é o popout, com `ItemRow.qml`,
    `StatusChip.qml`, `Mark.qml` e `BomDiaButton.qml`.
  - `BomDiaSettings.qml` são as configurações.

Daemon e interface se falam por `PluginService.setGlobalVar`:

- o daemon publica a variável `view` (`{ summary, busy }`) sempre que muda algo;
- a interface pede trabalho escrevendo `command` (`{ name, args, seq }`). O `seq` faz um pedido
  repetido ser executado de novo.

```
manifest          plugin.json (id bomDiaArtisan, tipo composite)
Model.js          todas as regras: normalização, filtros, cursor, marcas de lida, aviso, texto
Source.js         transporte: argv do curl, leitura da resposta (429, 404 da sondagem), checkDue
Actions.js        argv fixo para xdg-open e dms notify. Texto do feed nunca chega a um shell
Glyphs.js         cores, ícones e rótulos dos status (escapes \u, nunca caracteres literais)
test/             node --test, com a fixture de 4 edições de uma resposta real
```

```bash
npm test          # os testes do node e a checagem de glifos
```

Depois de mudar um `.qml`, reinicie o DMS (`systemctl --user restart dms`). Os `.js` são lidos de
novo com o mesmo restart.

Para ver erros de QML: `journalctl --user -u dms -f`.

### Não escreva glifos Nerd Font como caracteres literais

Os ícones são códigos da área privada de uso (U+E000–U+F8FF). Um caractere literal pode virar vazio
sem aviso. Escreva sempre como escape (`""`) em `.js` e `.qml`. `npm test` falha se houver um
caractere literal em qualquer arquivo, e `tools/escape-glyphs.py` corrige os que aparecerem.

---

## Diferenças em relação ao original (omarchy)

| Original (omarchy-shell) | Este port (DMS) |
|--------------------------|-----------------|
| O toast abre o painel ao clicar | O toast só avisa (`dms notify` não tem ação de clique) |
| Clique do meio abre a edição de hoje no site | Não portado: o `PluginComponent` expõe só clique esquerdo e direito |
| Comandos IPC (`open`, `close`, `toggle`, `refresh`, `markAllRead`) | Removidos. Os pedidos internos passam por `setGlobalVar`. |
| Um widget por monitor, com eleição de líder | Um daemon só, sem eleição |
| Configuração em `shell.json` | Configuração pela interface do DMS |

## Licença

[MIT](LICENSE). Copyright do original: m0u. Copyright do port: Adryel Dearo.
