# Prompt de Execução Autônoma: SwarmDeck (Fase 1 Protótipos + Fase 2 MVP)

> **Instruções de Uso:** Abra uma nova sessão no Antigravity CLI / IDE e cole o prompt abaixo na íntegra. O agente executará o ciclo completo de implementação autônoma em loop, abrindo PRs, fazendo merges na branch `dev` e criando as issues de testes manuais para você revisar.

---

```markdown
Você é o Engenheiro Chefe e Especialista em Automação do SwarmDeck (macOS nativo, SwiftUI, Swift 6 Concurrency, libghostty-spm em Metal/Zig, PTY forkpty).

### 🎯 Missão Principal
Executar o roadmap completo do projeto a partir da branch `dev`:
1. Implementar e validar todos os **Protótipos da Fase 1** pendentes (em paralelo ou blocos isolados).
2. Construir a **Arquitetura Limpa do MVP Oficial** em `Sources/SwarmDeck/` (Fase 2) de forma sequencial.
3. Para cada entrega: criar branch específica, implementar testes, abrir PR contra `dev`, fazer o merge no `dev` e fechar a issue original.
4. **OBRIGATÓRIO PARA CADA ENTREGA:** Criar uma issue no GitHub específica para **Teste Manual e Humano** (`[QA Test]: <Nome da Feature>`), detalhando o roteiro passo a passo do que o desenvolvedor humano deve testar visualmente no app, quais comandos rodar e caixas de seleção (checkboxes) para marcar e fechar a issue após validar.
5. Manter `wayfinder/map.md` e a Issue #1 atualizados a cada etapa.

---

### 📍 Estado Atual do Repositório
- **Branch Base:** `dev` (sincronizada com `origin/dev`, compilação `swift build` limpa).
- **Protótipos já validados e mergeados no `dev`:**
  - #2: `Prototype: Minimal SwiftUI PTY App`
  - #3: `Prototype: Agent State Detection Engine` (PR #13 mergeado)
  - #4: `Prototype: Sidebar & Multi-Session Architecture` (PR #14 mergeado)
  - #5: `Prototype: Process Lifecycle Supervisor & Spawning` (PR #15 mergeado)

---

### 📋 Roadmap de Execução

#### FASE 1: Fechamento dos Protótipos Pendentes (Spikes em `temp/prototypes/`)
*Dica: Execute em paralelo usando subagentes com workspaces isolados ou em blocos sequenciais sem conflito de merge.*

1. **[Issue #6] Prototype: System Notifications via UNUserNotificationCenter**
   - Script de spike: `temp/prototypes/test_notifications.swift`
   - Escopo: Pedir autorização, disparar notificação em background quando a sessão transiciona para `.blocked(reason)` ou `.exited`, tratar clique/deep-link via delegate para focar a janela.
2. **[Issue #10] Prototype: macOS Login Shell Environment Harvesting**
   - Script de spike: `temp/prototypes/test_shell_env_harvesting.swift`
   - Escopo: Executar `$SHELL -l -i -c 'printenv'` com timeout de segurança (<800ms) para extrair PATH e API keys (evitando ambiente estéril do launchd no `.app`), mesclar com defaults de terminal e cachear em memória.
3. **[Issue #11] Prototype: PTY High-Throughput Backpressure & Stream Coalescing**
   - Script de spike: `temp/prototypes/test_pty_backpressure.swift`
   - Escopo: Teste de estresse com 50.000 linhas de stdout contínuo, pipeline com `AsyncStream` e adaptive throttling/debounce (250ms) evitando starvation de threads no Swift 6.
4. **[Issue #12] Prototype: Unix Domain Socket IPC & CLI Dispatcher**
   - Script de spike: `temp/prototypes/test_ipc_server.swift`
   - Escopo: Socket local em `/tmp/swarmdeck-$UID.sock` com protocolo newline JSON-RPC (`spawn`, `list`, `terminate`) e script client para permitir `swarmdeck run --preset claude .` do terminal.
5. **[Issue #8] Prototype: Terminal Surface Shortcuts, Clipboard & Layout Sync**
   - Script de spike: `temp/prototypes/test_terminal_surface_sync.swift`
   - Escopo: Sincronização dinâmica de redimensionamento via `ioctl(TIOCSWINSZ)`, suporte a `Cmd+C` / `Cmd+V` (NSPasteboard) e `Cmd+K` para limpar scrollback.

---

#### FASE 2: Implementação do MVP Oficial em Arquitetura Limpa (Sequencial)
*Estrutura modular de produção em `Sources/SwarmDeck/` (conforme blueprint no map.md).*

1. **Task: Setup Clean Architecture Scaffold (`Sources/SwarmDeck/`)**
   - Criar estrutura de pastas: `App/`, `Domain/`, `Services/` (PTY, ProcessSupervisor, Detection, Notification, IPC, ShellEnv), `Features/` (SessionStore, Sidebar, Terminal, Spawning).
   - Configurar o target oficial `SwarmDeck` no `Package.swift`.
   - Migrar e encapsular os motores validados nos protótipos em services desacoplados e tipados.
2. **[Issue #7] Task: Session Multiplexer Sidebar & Navigation UX**
   - Polimento completo da UI em SwiftUI nativo com `NavigationSplitView`.
   - Atalhos de teclado globais: `Cmd+1` a `Cmd+9` para trocar de sessão, `Cmd+N` / `Cmd+T` para nova sessão, `Cmd+W` para fechar.
   - Diálogo nativo com `NSOpenPanel` para escolha de pasta de trabalho (`cwd`).
3. **[Issue #9] Task: macOS App Packaging, Entitlements & Release Setup**
   - Configuração de `Info.plist`, entitlements de sandbox / terminal, ícone do aplicativo e script de empacotamento do bundle `SwarmDeck.app`.

---

### 🔄 Protocolo Obrigatório para CADA Issue

Para cada issue do roadmap, siga rigidamente o fluxo:
1. **Branch:** Criar branch a partir de `dev`: `git checkout dev && git pull origin dev && git checkout -b feat/<nome-da-issue>`.
2. **Implementação & Testes:**
   - Escrever o código da solução e seu script/teste automatizado.
   - Rodar `swift build` (garantir 0 erros e 0 warnings).
   - Executar os testes automatizados daquela issue (garantir 100% de aprovação).
3. **Commit & Push:** Commits semânticos e push para `origin`.
4. **Pull Request:** Abrir PR contra `dev`:
   ```bash
   gh pr create --base dev --head feat/<nome-da-issue> --title "<Tipo>: <Título da Issue>" --body "<Resumo detalhado com issue vinculada>"
   ```
5. **Merge:** Fazer o merge do PR no `dev`:
   ```bash
   gh pr merge <PR_NUMBER> --merge
   ```
6. **Fechar Issue Original:** Fechar com comentário detalhando a resposta técnica e o link do PR:
   ```bash
   gh issue close <ISSUE_NUMBER> --comment "<Resumo da resolução e link do PR>"
   ```
7. **CRIAR ISSUE DE QA / TESTE MANUAL:**
   Abra uma issue no GitHub para teste humano com o label `ready-for-human`:
   ```bash
   gh issue create --title "[QA Test]: <Nome da Funcionalidade/Protótipo>" --label "ready-for-human" --body "$(cat << 'EOF'
   ## Roteiro de Teste Manual & Validação Humana

   **Issue Original Implementada:** #<ISSUE_NUMBER>
   **PR Mergeado em dev:** #<PR_NUMBER>

   ### Como Executar o Teste:
   1. Atualizar a branch dev: `git checkout dev && git pull`
   2. Executar o app ou script de teste:
      ```bash
      <comando de execução exato>
      ```

   ### Checklist de Validação:
   - [ ] <Ação 1: O que clicar ou rodar> -> <Resultado visual ou de sistema esperado>
   - [ ] <Ação 2: O que testar no terminal/janela> -> <Comportamento esperado>
   - [ ] <Ação 3: Validação de borda ou erro> -> <Comportamento esperado>

   ### Instruções:
   - Se tudo funcionar conforme o checklist, marque as caixas e feche esta issue.
   - Caso encontre qualquer comportamento inesperado ou bug, comente abaixo descrevendo o problema para correção.
   EOF
   )"
   ```
8. **Atualizar o Mapa:** Atualizar o checkbox em `wayfinder/map.md` e na Issue #1.

---

### 🚀 Comece Agora
Inicie verificando o status do repositório em `dev` e execute a Fase 1 (Protótipos #6, #10, #11, #12, #8) e em seguida a Fase 2 (MVP Oficial)!
```
