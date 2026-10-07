# Continuação no Codex: OpenScreen + Iriun Webcam no Windows

## Progresso da implementação experimental (2026-10-07)

O estado abaixo substitui a proposta histórica descrita no restante deste arquivo:

- A proposta foi conferida com `git apply --check` antes das alterações. O código
  ainda tinha o retorno direto de `configureReader`. A correção agora está no
  C++, e `patches/iriun-webcam-fallback.patch` foi removido para não deixar uma
  segunda alteração para aplicar por engano.
- `WebcamCapture::initialize` usa uma única sequência MF -> limpeza -> DirectShow,
  incluindo falhas de configuração do leitor. Uma segunda falha também libera os
  recursos. A identidade original, o tamanho e o FPS solicitados continuam sendo
  enviados ao DirectShow. Um CLSID ausente/inválido continua falhando sem escolher
  outra câmera. O backend só é confirmado após sucesso, e seus getters existentes
  mantêm o contrato BGRA do DirectShow mesmo quando NV12 foi solicitado ao MF.
- `webcam_backend_test.cpp` cobre oito combinações de sucesso/falha nos estágios de
  startup, seleção, configuração e fallback, incluindo ordem de limpeza e estado
  de posse do dispositivo. Ele é compilado e executado pelo build nativo Windows,
  e pode ser executado com g++ no Linux. Esses testes usam operações simuladas;
  não comprovam o funcionamento de Media Foundation, COM ou do driver Iriun.
- `.github/workflows/iriun-windows-experimental.yml` roda somente no fork,
  somente Windows x64, automaticamente ao enviar estas alterações à branch ou
  manualmente. Compila Whisper/STT com Vulkan e CPU a partir do mesmo checkout,
  sem depender de artefatos STT que um fork novo não possui. Mantém os gates de
  `before-pack.cjs`, verifica carregamento do STT/compositor com PATH mínimo e
  testa o Studio no aplicativo empacotado antes de criar o ZIP.
- `electron-builder.iriun.json5` mantém os recursos da configuração existente,
  mas dá identidade/nome próprios ao experimento e não publica releases. O ZIP
  inclui `Abrir-OpenScreen-Iriun.cmd`, que usa `data/` ao lado do aplicativo.
  Projetos da instalação principal não são abertos nem migrados automaticamente.
- A causa específica da Iriun continua sem confirmação. Se o MF inicializar mas
  não entregar frames, ou se o DirectShow também falhar, esta correção de
  inicialização pode não resolver. Os novos logs de backend/formato e os HRESULTs
  existentes devem orientar a próxima tentativa.

Resultados desta continuação e eventual artefato devem ser informados com o
commit/run efetivamente executados. O teste físico Windows + Iriun permanece
pendente porque o ambiente do agente não tem esse dispositivo.

## Objetivo do usuário

O usuário quer gravar a tela com a câmera do celular fornecida pelo Iriun Webcam. O OpenScreen lista a Iriun, mas, ao iniciar a gravação, informa um problema com a câmera; o vídeo resultante fica sem webcam. A causa ainda não foi confirmada. Não há diagnóstico JSON, mensagem técnica completa ou confirmação de que a prévia funcione.

Ele não quer instalar manualmente Visual Studio Build Tools, CMake, Ninja, Rust e LLVM. Priorize editar/testar o código no ambiente do agente e compilar o aplicativo Windows no GitHub Actions do fork. A meta é entregar um artefato Windows pronto para um teste, não apenas instruções de compilação.

## Repositório e ponto de retomada

- Fork autorizado: `capitv/openscreen`.
- Upstream: `getopenscreen/openscreen`.
- Branch criada nesta conversa: `fix/iriun-webcam-compat`.
- Base consultada: `e8b85444f21623a779c53033424511a58a971bf7`.
- Commit que adicionou a proposta de patch: `a649d6ef6d6d2a9e6fe72b53d46cc4a52ef10124`.
- Proposta: `patches/iriun-webcam-fallback.patch`.
- Este arquivo é contexto de transição, não uma correção executável.

No momento desta transição, a branch contém o ARQUIVO de patch, mas a alteração ainda NÃO foi aplicada ao `webcam_capture.cpp` nessa branch. Nenhum workflow específico para essa correção foi adicionado e nenhum instalador desta correção foi produzido ou validado. Não trate a presença do `.patch` como código já corrigido. Releia o estado atual, pois o usuário ou outro agente pode ter avançado depois.

O usuário também tem uma cópia local em `E:\openscreengit` e relatou ter seguido os passos de aplicação do patch; o estado dessa pasta não foi inspecionado. Se estiver trabalhando localmente, confira `git status`, os remotes e o diff antes de mudar de branch. Preserve alterações e arquivos existentes. Não suponha que `origin` aponta para o fork: a pasta pode ter vindo do upstream ou de um ZIP. Essa pasta não é necessária para a abordagem na nuvem.

## Investigação técnica já realizada

Leia `AGENTS.md` e a documentação de build do repositório antes de alterar código.

Arquivo principal: `electron/native/wgc-capture/src/webcam_capture.cpp`, função `WebcamCapture::initialize`.

A implementação consultada tenta Media Foundation e usa DirectShow em determinadas falhas anteriores à configuração do leitor. Porém, depois de selecionar a câmera, termina com:

```cpp
return configureReader(requestedWidth, requestedHeight, fps_, preferNv12);
```

Portanto, uma falha nessa configuração não chega ao fallback DirectShow. A proposta armazenada no patch mantém o caminho de sucesso e, após falha de `configureReader`, libera os recursos com `stop()` e tenta `directShowCapture_.initialize(...)` com a seleção original.

Isso é uma hipótese de correção para uma lacuna real no fluxo, NÃO um diagnóstico confirmado da Iriun. Se o dispositivo já falha em DirectShow, essa proposta pode não ajudar. Inspecione também:

- `electron/native/wgc-capture/src/dshow_webcam_capture.cpp` e os headers correspondentes;
- resolução do CLSID e seleção da câmera em `electron/ipc/handlers.ts`;
- `electron/recording/deviceNameMatching.ts`;
- configuração de formato, ausência de frames e logs do helper.

Não substitua uma câmera explicitamente selecionada por outra. Valide limpeza de recursos, formato negociado, estado do backend e comportamento quando não existe CLSID DirectShow utilizável. Não adicione uma exceção específica para a marca Iriun sem evidência.

## Trabalho a executar

1. Confirme acesso de leitura/escrita ao fork e busque a branch existente. Faça as alterações nela ou em uma branch de trabalho derivada dela; não altere o upstream nem sobrescreva a `main` sem necessidade.
2. Revise a proposta e execute `git apply --check patches/iriun-webcam-fallback.patch` antes de aplicar. Não force um patch incompatível nem aplique duas vezes. Se for necessário, implemente a mudança mínima diretamente no arquivo completo e atualize/remova a proposta redundante de forma explícita.
3. Acrescente testes apropriados ao comportamento novo. Registre os testes realmente executados; mocks ou testes de fluxo não comprovam compatibilidade com o driver real. Os testes relatados anteriormente no chat não substituem uma execução verificável nesta tarefa.
4. Prepare uma compilação Windows x64 no GitHub Actions do fork, preferencialmente limitada a Windows e a esta tarefa. Leia os scripts reais em vez de presumir que `npm run build` ou `npm run dev` compila os componentes nativos.
5. Publique as alterações somente no fork. Inicie a execução se as credenciais e permissões disponíveis permitirem. Se faltar autorização para push, edição de workflows ou execução, informe a operação exata bloqueada e peça somente a intervenção necessária. Nunca peça tokens ou senhas no chat.
6. Acompanhe a execução durante a tarefa, investigue logs e corrija falhas de build. Disponibilize um artefato pronto, com identificação experimental e commit de origem. Não crie release pública nem envie PR ao upstream sem solicitação.

## Pontos importantes da compilação

Leia `package.json`, `.github/workflows/build.yml`, `.github/actions/setup/action.yml`, `technical-documentation/engineering/build-and-packaging.md`, `scripts/build-windows-wgc-helper.mjs`, `scripts/build-windows-compositor-addon.mjs` e `scripts/before-pack.cjs`.

A versão consultada declara Node 22.22.1 e npm 10.9.4. Use as versões efetivamente declaradas pelo checkout. O comando Windows existente é `npm run build:win -- --publish never`; ele inclui compilação nativa, preparação de dependências e empacotamento. Verifique os pré-requisitos no runner.

A captura usa C++/MSVC, Windows SDK, CMake/Ninja. O compositor usa Rust/MSVC, LLVM/libclang e o SDK FFmpeg fixado em `crates/.cargo/config.toml`. Compile com um ambiente Windows adequado; a mera disponibilidade de um terminal no ambiente do agente não garante esses compiladores.

**Não ignore o Whisper/STT:** o workflow upstream chama `scripts/stage-whisper-stt.sh`. Esse script procura uma execução bem-sucedida com os mesmos fontes no repositório indicado por `GITHUB_REPOSITORY`; um fork novo pode não ter esses artefatos. Planeje construir os binários necessários ou obter artefatos upstream comprovadamente correspondentes aos fontes, com as permissões e a integridade verificadas. Não desative as verificações de empacotamento nem entregue funções silenciosamente quebradas só para conseguir um build verde. Consulte `.github/workflows/build-whisper-stt.yml` e `scripts/build-whisper-stt.sh`.

Prefira runner hospedado padrão e execução limitada; não use runners pagos especiais sem aprovação. Não dependa de segredos de assinatura ou publicação do mantenedor upstream. Uma build experimental sem assinatura deve ser identificada como tal; não desative proteções do Windows.

## Entrega e limites de validação

Entregue o artefato real (ou o link verificável do run/artefato), branch/commit, resumo da alteração e resultados dos testes. Distinga claramente:

- alteração implementada;
- testes automatizados concluídos;
- aplicativo compilado/empacotado;
- teste real com Iriun no PC do usuário.

Sem acesso a uma sessão Windows com Iriun conectada, a última etapa está pendente, nunca aprovada. Não anuncie a câmera como corrigida só porque a compilação passou.

Oriente um teste curto com o aplicativo experimental separado da instalação principal, preservando projetos e dados. Se a câmera ainda falhar, peça o diagnóstico gerado imediatamente após a tentativa; o repositório documenta `Save Diagnostics` e o modo `OPENSCREEN_DIAGNOSTIC=1`. Revise informações pessoais nos logs antes de publicá-los.

Comunique-se em português. O usuário prefere que o agente execute o trabalho disponível e peça apenas autorizações ou ações que dependam realmente dele.
