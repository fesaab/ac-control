# AC Control

App nativo macOS para controlar o LG Dual Inverter pela barra de menus, usando a API oficial LG ThinQ Connect. Uso pessoal; macOS 14 ou posterior; Apple Silicon ou Intel conforme a arquitetura da compilação.

## Comportamento

- Ligado: ícone de frio + temperatura configurada / ícone de termômetro + temperatura ambiente na barra. O tooltip identifica cada leitura.
- Desligado: ícone de termômetro + temperatura ambiente.
- Falha de conexão, estado desconhecido, leitura essencial ausente ou consulta vencida: somente ícone de alerta, com explicação no tooltip e no painel.
- Clique abre painel rápido com ligar/desligar, slider de temperatura, seletor de velocidade do ventilador e leitura ambiente. Arrastar mostra o valor; soltar envia um único ajuste.
- Configurações abre janela separada com todos os dispositivos retornados pela conta, nome/tipo/modelo e seleção do ar-condicionado. A lista pode ser atualizada; dispositivos de outros tipos ficam visíveis, com controle indisponível. Também há intervalo de consulta, início automático e acesso ao `.env`.
- Ligar envia somente o comando de energia: preserva modo e temperatura existentes.
- O slider usa os limites, passo e exclusões de escrita do perfil LG em Celsius. Sem perfil válido, sem escrita. Modos sem ajuste de temperatura mantêm o controle desativado.
- Início automático solicitado por padrão ao abrir o app real empacotado; o macOS pode exigir aprovação em Geral → Itens de Início. A demonstração não registra início automático.

## Executar localmente

Requer Command Line Tools da Apple com Swift 6 ou posterior e Swift Testing. Os testes usam Swift Testing com XCTest desativado, sem depender do Xcode completo. O script carrega explicitamente o plugin de macros quando o Command Line Tools não o descobre automaticamente. Não há dependências externas de runtime nem servidor próprio.

```sh
cd ~/github/fesaab/ac-control
make test
make app
```

App gerado: `dist/AC Control.app`. A assinatura é ad hoc, destinada ao uso local neste Mac. Não é um pacote notarizado para distribuição.

Para testar interface sem acessar a LG:

```sh
make demo
```

A demonstração mostra DEMO no painel, usa dados fictícios e permite alternar ligado/desligado, offline e sensor ausente na janela de configurações. Não lê token, não faz chamadas HTTP e não registra início automático.

Para uso real, configure o token e abra `dist/AC Control.app` no Finder, ou execute `make run`. Isso inicia consultas à sua conta LG. Botões e slider enviam comandos ao aparelho selecionado.

## Token LG

1. Acesse https://connect-pat.lgthinq.com/tokens com a mesma conta do aplicativo LG ThinQ.
2. Clique em **Create new token**. Nome sugerido: `Ar Mac`.
3. Marque **Device List Retrieval**, **Device Status Inquiry** e **Device Control**.
4. Clique em **Create Token** e copie o PAT.
5. Edite `.env` local:

```dotenv
LG_THINQ_PAT=cole_seu_token_localmente
LG_THINQ_COUNTRY=BR
LG_THINQ_REGION=AIC
LG_THINQ_CLIENT_ID=
```

O arquivo `.env` já foi criado com token vazio, permissão 0600 e está ignorado pelo Git. Não há uso do Keychain. O token não é embutido no executável, não vai para UserDefaults e não é impresso em logs. O app lê esse arquivo mesmo quando aberto pelo Finder ou no início da sessão. Após mudar o arquivo, clique em **Recarregar configuração**.

País/região devem corresponder à conta LG. BR utiliza AIC; outras regiões documentadas pela LG são EIC e KIC. A escolha do aparelho é feita somente em Configurações → Dispositivos da conta, inclusive no primeiro uso com um único ar. Ela fica salva neste Mac e é restaurada ao reabrir o app. `LG_THINQ_CLIENT_ID` é opcional: o app gera um UUID estável e o salva localmente; não gera um cliente a cada consulta.

Variáveis de ambiente do processo com prefixo `LG_THINQ_` têm prioridade sobre `.env`. `AC_CONTROL_ENV_FILE` permite indicar outro arquivo. O caminho do `.env` do projeto é gravado no Info.plist durante a compilação; ao mover a pasta, recompile. Não copie `.env` para dentro do bundle.

## Ventilador

O painel rápido mostra a velocidade atual e permite escolher somente valores de escrita publicados pelo perfil LG do aparelho selecionado. O controle prefere `airFlow.windStrengthDetail`, aceita `windStrength` quando necessário e usa níveis numéricos de `windStep` quando este for o formato disponível. Automático, Baixa, Média, Alta e Turbo só aparecem se estiverem entre as opções retornadas pela LG.

Com o ar desligado, conexão indisponível, consulta vencida ou comando em andamento, o seletor fica desativado. Sem suporte de escrita no perfil, o painel informa “Indisponível”. Uma leitura ausente não é interpretada como Automático.

Alterar ventilação envia somente a propriedade correspondente em `airFlow`, preservando modo, temperatura e energia. O app envia uma requisição e confirma a velocidade por leituras subsequentes; não repete o comando em timeout. O aparelho pode recusar uma velocidade no modo atual; o app mostra o erro sem mudar de modo automaticamente.

## Seleção do dispositivo

No primeiro uso, configure o PAT e abra **Configurações → Dispositivos da conta**. Clique no ar-condicionado desejado. A seleção é salva pelo ID em UserDefaults; nenhum token é salvo nesse armazenamento. A barra e o painel passam a usar nome, perfil e leituras do aparelho escolhido. Trocar a seleção invalida imediatamente perfil/leituras anteriores antes de consultar o novo aparelho.

**Atualizar lista** refaz a descoberta da conta. Dispositivos de outros tipos são listados para identificação e ficam desabilitados para controle. Ares com nomes iguais exibem o ID para distinção. Se o aparelho salvo desaparecer, o app pede outra escolha e não muda automaticamente de ambiente. Falhas na descoberta mantêm a lista anterior visível com aviso e suspendem os controles até confirmar o estado novamente.

## Atualização e confirmação

Consulta padrão a cada 60 segundos e ao abrir o painel. Intervalo configurável: 30, 60, 120 ou 300 segundos. Falhas repetidas aumentam o intervalo até 15 minutos. Após repouso do Mac, o estado anterior é invalidado e consultado novamente.

Um comando POST é enviado uma única vez. O app consulta estado até três vezes para confirmar o resultado. Não anuncia sucesso apenas porque a LG aceitou a requisição; não repete comando em timeout. Um erro pode significar resultado ainda não confirmado: atualize antes de tentar de novo.

Temperatura ambiente é a leitura fornecida pelo sensor do ar. A nuvem pode retornar dados em cache, especialmente com o aparelho desligado. O horário mostrado é da consulta LG e não garante o instante da amostragem do sensor. A atualização do sensor com o aparelho desligado e a compatibilidade integral deste modelo ainda precisam de validação real.

A ficha técnica do conjunto S3-Q09AA31A, com unidade S3NQ09AA31A.EB2GAM1, documenta ajuste pelo controle de 18–30 °C. A faixa de temperatura interna 18–32 °C é outra especificação. O app respeita o perfil efetivamente retornado pelo ThinQ Connect, inclusive se diferir dessa ficha.

## Estrutura e testes

`ACControlCore`: parsing de configuração, contrato HTTPS, perfil, estado, permissões e payloads. `ACControl`: UI SwiftUI em NSPopover/NSStatusItem, configurações e início automático. Testes usam transporte HTTP em memória; não acessam LG, rede local ou aparelho.

```sh
./scripts/test.sh
./scripts/build-app.sh
open -n "dist/AC Control.app" --args --demo --show-panel
```

## Prévias nativas

O app pode renderizar o próprio painel e a janela de configurações em modo demo, sem automação de tela e sem rede:

```sh
"dist/AC Control.app/Contents/MacOS/ACControl" --demo --render-previews /tmp/ac-control-preview
```

Esse comando também verifica em memória a listagem de três dispositivos, a troca entre dois ares, a rejeição de seleção de uma lavadora, o ajuste para 25 °C e a preservação da temperatura ao desligar/ligar.

## Fontes técnicas

- SDK oficial LG (contrato, headers, perfil e comandos): https://github.com/thinq-connect/pythinqconnect
- API oficial: https://smartsolution.developer.lge.com/en/apiManage/thinq_connect
- Ficha técnica LG, págs. 3 e 5, hospedada por distribuidor: https://strar.vteximg.com.br/arquivos/catalogo-hw-dual-inverter-voice-ai-r32-9k.pdf
- Apple NSStatusItem: https://developer.apple.com/documentation/appkit/nsstatusitem
- Apple SMAppService: https://developer.apple.com/documentation/servicemanagement/smappservice

O header x-api-key utiliza a chave pública de cliente publicada no SDK LG; ela não substitui o PAT pessoal. Contrato implementado de forma independente em Swift. Consulte THIRD_PARTY_NOTICES.md.
