# Trilha Apostólica

Aplicativo web instalável (PWA) para coordenação e alunos, com a identidade visual oficial.

- Cadastro de alunos e turmas, notas e chamada por data.
- Perfis e equipe de coordenação com contas individuais.
- Cadastro autônomo de alunos com confirmação de e-mail e aprovação dentro do app.
- Área do aluno com notas, frequência e avisos próprios.
- Materiais e atividades opcionais, sem efeito na média.
- Financeiro individual com cobranças, vencimentos e confirmação manual de pagamentos.

## Rodar localmente

Requer **Node.js 22 ou superior**.

```bash
npm ci
npm start
```

Abra **http://127.0.0.1:4173**. A aplicação está em `dist/` e a biblioteca do Supabase
já vem incluída. Para recompilar essa biblioteca, execute `npm run build`.

## Banco existente

Mover o código para o GitHub **não exige recriar o Supabase**. Use o mesmo projeto,
a mesma URL e a mesma chave pública. Os dados online permanecem no banco existente.
Não é necessário executar os SQLs novamente apenas por trocar a hospedagem.

## Conexão automática em todos os dispositivos

Configure uma vez no **ambiente de build do Cloudflare**:

| Variável | Valor |
| --- | --- |
| `PUBLIC_SUPABASE_URL` | Project URL do projeto que já usa |
| `PUBLIC_SUPABASE_KEY` | Chave pública Publishable ou anon |

Execute um novo build/deploy depois de salvar. O comando `npm run build` gera
`dist/config.js` com essa configuração pública. O Wrangler também executa esse
build antes de publicar. Não use service_role ou sb_secret; o build rejeita essas
chaves. Valores não são impressos nos logs pelo gerador.

Com a configuração padrão, qualquer dispositivo abre direto no login. Cada pessoa
entra com seu e-mail e senha e recebe somente os acessos autorizados no banco.
Não há configuração de chaves por participante, nem alteração das permissões RLS.
A configuração da publicação prevalece sobre projetos antigos salvos no navegador.
Os links compartilhados passam a usar somente o endereço limpo do aplicativo.

Sem essas variáveis, permanece disponível o modo anterior: configuração manual
por navegador em Configurações. Senhas e registros reais não fazem parte do repo.

Para um projeto Supabase novo, siga o [guia de implantação](docs/IMPLANTACAO.md).

## Hospedagem

Conecte este repositório à plataforma escolhida e configure:

| Campo | Valor |
| --- | --- |
| Instalação | `npm ci` |
| Build | `npm run build` |
| Diretório de publicação | `dist` |
| Node.js | 22 ou superior |

O projeto é estático, sem servidor obrigatório em produção. Use HTTPS para instalar
no iPhone. Este repositório não ativa uma hospedagem automaticamente; a publicação
anterior continua independente até configurar a troca de endereço.

## Cloudflare

Para publicar no **Cloudflare Pages**, conecte este repositório e configure
**branch `main`**, **framework `None`**, **build `npm run build`** e **saída `dist`**.
O Node 22 está declarado em `.nvmrc`. Também há um `wrangler.jsonc` para a opção
Workers com assets estáticos. Veja o [passo a passo do Cloudflare](docs/CLOUDFLARE.md).

## Testes

```bash
npm run check
npm test
```

Para testes de interface:

```bash
npx playwright install chromium
```

Deixe `npm start` em outro terminal e execute `npm run test:browser`.
Em Linux, `npx playwright install --with-deps chromium` também instala dependências
do navegador. Para usar um Chromium existente, defina
`PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` com seu caminho.
Os testes usam dados fictícios e não consultam o banco real da igreja.

## Pastas

- `dist/`: aplicativo pronto para publicar.
- `src/`: entrada da biblioteca oficial do Supabase.
- `supabase/`: esquema completo e atualizações.
- `assets/`: logo original.
- `scripts/`: servidor local.
- `qa/`: testes de regras, permissões e interface.
- `docs/`: implantação e [referência técnica](docs/REFERENCIA.md).

## Cadastro de alunos sem criação manual no Supabase

A tela de entrada oferece Criar conta. O aluno informa nome, e-mail e senha,
confirma o e-mail e entra. A conta fica aguardando aprovação, sem acesso aos
registros da escola. Em Área do aluno > Solicitações de cadastro, a coordenação
confere o e-mail, seleciona o cadastro correto e aprova. Se o aluno ainda não
estiver no cadastro escolar, pode criá-lo pela própria tela de aprovação.

Para atualizar um banco existente, execute `dist/self-registration.sql` (inclui
os requisitos da área do aluno) e clique em Atualizar acesso. O esquema completo
já inclui o módulo para bancos novos. Não altera registros escolares existentes.

Uma vez no Supabase, habilite Allow new users to sign up em Authentication e
mantenha Confirm email habilitado. Em URL Configuration, configure Site URL e
Redirect URLs com a URL real do aplicativo no Cloudflare. A confirmação de e-mail
é enviada pelo serviço de Authentication do próprio projeto.

Contas novas nunca recebem acesso de coordenação automaticamente. Solicitações
não aprovadas não podem ler notas, presença, financeiro nem dados de outros
alunos. Apenas os coordenadores autorizados podem aprovar ou recusar. A aprovação
não substitui silenciosamente uma conta já vinculada a outro usuário.

Se houver várias equipes no mesmo projeto, compartilhe o link gerado em
Solicitações > Copiar link de cadastro. O link identifica a equipe sem expor
listas de alunos ou dados de coordenação. Em um projeto novo, o responsável pode
precisar clicar em Ativar cadastro depois de criar a primeira escola.

## Quizzes e ranking semanal por turma

A coordenação cria quizzes em **Quizzes > Novo quiz**, com enunciado, 2 a 6
alternativas, resposta correta e explicação opcional. Cada quiz pertence a uma
turma e semana. É possível salvar rascunho, publicar, encerrar e criar cópia.
Após publicar, perguntas, gabarito, turma e semana ficam protegidos; use uma cópia
para novas questões. O aluno responde em **Quiz** e consulta o resultado e o
ranking da própria turma. O ranking soma acertos da primeira tentativa finalizada
de cada quiz da semana, de segunda a domingo, no horário de São Paulo. Empates
compartilham a posição. A participação é opcional e não altera as notas.

Em banco existente com a área do aluno já instalada, execute `dist/quizzes.sql`
no SQL Editor do Supabase e atualize os dados no app. Também há um botão para
baixar o SQL na aba Quizzes enquanto o módulo não estiver ativado. O esquema
completo já inclui esse módulo para instalações novas. Não é necessário alterar
as variáveis do Cloudflare. O modo local permite preparar questões e visualizar
uma prévia; as tentativas oficiais e o ranking usam o Supabase.

A correção acontece no servidor. O gabarito não é enviado antes da finalização;
os alunos não podem escrever pontuação nem consultar tentativas de colegas.
Quizzes encerrados preservam os pontos já obtidos. Só alunos com acesso aprovado
participam; o ranking apresenta nome e acertos, sem contatos ou dados financeiros.

## Resumos, prévia e recuperação de senha

A página inicial da coordenação reúne cadastros pendentes, cobranças vencidas e
alunos com duas ou mais faltas nas últimas quatro chamadas registradas da turma
atual. Justificativas não contam como faltas. Os atalhos levam ao cadastro,
financeiro filtrado por atraso e acompanhamento.

O aluno vê o próximo vencimento, eventuais atrasos, os quizzes disponíveis da
semana e os avisos importantes. A prévia do quiz permite à coordenação conferir
o gabarito e as explicações antes de publicar, sem registrar tentativa. O ranking
permite navegar pelas semanas anteriores e destaca as três primeiras posições,
preservando empates e a separação por turma.

Na entrada, **Esqueci minha senha** envia o link de recuperação pelo Supabase.
O aluno define e confirma a senha nova no próprio app. A URL do aplicativo deve
continuar cadastrada em Authentication > URL Configuration (Site URL e Redirect
URLs); usa a mesma configuração dos e-mails de confirmação. Estas melhorias não
exigem SQL adicional. O módulo de quizzes continua exigindo sua migração inicial.

## Aprender: livros, materiais e quiz

No menu dos alunos, **Aprender** reúne duas seções: **Livros e materiais**
(textos e links HTTPS para livros, PDFs e materiais didáticos) e **Quiz e ranking**.
O quiz substitui as antigas atividades de resposta livre. O atalho da página
inicial abre diretamente essa seção, com Aprender marcado no menu. As notas,
a primeira tentativa oficial e o ranking por turma continuam com as mesmas regras.

As atividades antigas deixam de aparecer para os alunos, mas seus registros e
respostas são preservados no histórico da coordenação, em Área do aluno. Novos
conteúdos nessa tela são materiais de apoio; novas atividades são criadas em
Quizzes. Essa reorganização não exige alteração no banco de dados.

## Resultados por questão

A coordenação acessa **Quizzes > Resultados** em cada quiz publicado ou encerrado.
O relatório apresenta o total de tentativas finalizadas, o percentual geral de
acertos, os acertos e erros por questão e a distribuição das alternativas.
As perguntas com mais erros aparecem primeiro, com o gabarito e a explicação para
ajudar na revisão da aula. O contexto mostra a turma e a semana do quiz.

O relatório usa somente as primeiras tentativas já registradas e não altera notas
nem pontuação. Respostas são consultadas sob as permissões existentes da
coordenação, paginadas para evitar o limite padrão de registros do Supabase.
Alunos não têm acesso a esse relatório. Não requer SQL adicional; o módulo
original de quizzes deve estar instalado. Sem tentativas, o relatório informa
que ainda não há respostas, sem apresentar um percentual artificial de zero.

## Agendamento dos quizzes

Em **Quizzes > Novo quiz / Editar quiz**, informe **Abertura programada** e
**Encerramento programado** e salve como publicado. É possível preparar quizzes
para semanas futuras. Os horários são interpretados no fuso America/Sao_Paulo,
independentemente do fuso do dispositivo, e devem estar dentro da semana escolhida.
Deixar os campos vazios mantém o comportamento anterior: segunda às 00h até a
segunda seguinte às 00h (encerramento exclusivo).

Para atualizar um banco existente, execute `dist/quiz-scheduling.sql` no SQL
Editor do Supabase e atualize os dados no app. O editor oferece o download desse
arquivo. O esquema completo e a instalação de quizzes já incluem o agendamento.
A atualização preserva as notas, os quizzes e as tentativas existentes.

O banco controla o período de resposta, mesmo com o aplicativo fechado. Antes da
abertura, os alunos veem o aviso de agendamento da semana, sem acesso às questões.
Depois do encerramento, não são aceitas novas tentativas; quem já respondeu
mantém acesso ao resultado e seus pontos continuam no ranking. Uma resposta só
é aceita se for finalizada antes do horário de encerramento. A tela de quizzes
atualiza os dados a cada 30 segundos quando visível e sem uma resposta em edição.
Encerrar manualmente desativa novas respostas; reabrir respeita o período salvo.
A coordenação pode editar os horários sem apagar as tentativas.

## Busca e acompanhamento individual

Em **Aprender > Livros e materiais**, a busca filtra o título e a descrição dos
materiais publicados para a turma. Não diferencia maiúsculas nem acentos e aceita
mais de uma palavra. Não pesquisa o conteúdo interno de PDFs ou sites vinculados.
O filtro não inclui as atividades antigas do histórico.

A coordenação abre o acompanhamento individual pelo botão **Acompanhar aluno**
(ícone de gráfico) em **Alunos** ou tocando no nome em **Acompanhamento**. A tela
reúne média, evolução cronológica das notas, chamadas com justificativas e as
primeiras tentativas dos quizzes, incluindo acertos e aproveitamento. Os
históricos podem incluir turmas anteriores; cada registro identifica sua turma.
As notas das avaliações e os resultados dos quizzes permanecem separados.

A consulta dos quizzes usa as permissões existentes da coordenação e filtra o
aluno e a equipe no servidor, com paginação. Uma falha no módulo de quizzes não
impede a consulta das notas e presenças, nem é apresentada como zero participações.
Não exige SQL adicional. Alunos continuam sem acesso ao relatório da coordenação.

## Aulas gravadas e anotações privadas

A coordenação cadastra aulas em **Área do aluno > Aulas gravadas > Nova aula
gravada**. Informe título, turma, data, link do YouTube, descrição e material de
apoio opcional. Salve como publicado para aparecer em **Aprender > Aulas gravadas**.
O vídeo deve permitir incorporação. O YouTube pode exigir verificação da conta
para uploads com mais de 15 minutos. Vídeos não listados não aparecem na busca,
mas quem possui o link pode compartilhá-lo. O acesso à página no app é por turma;
o link do YouTube não é uma barreira de acesso ao arquivo de vídeo.

Execute `dist/recorded-lessons.sql` no SQL Editor do Supabase existente e atualize
os dados no app. Requer a área do aluno já instalada. A seção administrativa
oferece o download do SQL. O esquema completo inclui o módulo para bancos novos.

O aluno assiste no player incorporado do YouTube e escreve em Minhas anotações.
O texto e a marcação manual de aula assistida são salvos automaticamente após
uma pausa na edição, com opção de salvar imediatamente. As notas são privadas:
colegas e coordenadores não podem consultá-las. Rascunhos, aulas arquivadas e
outras turmas ficam bloqueados pelas regras do banco. Prévia da coordenação e
modo local não gravam anotações pessoais.

O salvamento usa revisão para impedir que outra janela sobrescreva silenciosamente
o texto. Em erro, a anotação permanece na tela; o aluno pode tentar novamente ou
baixar uma cópia. Fechar/Esc tenta salvar primeiro. Fechar sem salvar exige
confirmação quando existem alterações pendentes. Recarregar ou sair com mudanças
pendentes aciona o aviso do navegador. Isso não fornece salvamento offline: em
falha de rede, mantenha a aula aberta ou baixe uma cópia do texto.

Após a primeira publicação, vídeo e turma são fixados para preservar o contexto
das anotações; use uma nova aula para outro vídeo. Arquivar desativa o acesso sem
apagar as anotações; republicar restaura o acesso do aluno autorizado. Não há
exclusão de aulas pela interface. A marcação de assistida é autodeclarada, sem
rastrear a posição de reprodução nem alterar notas, frequência ou ranking.

## Interface essencial

As telas de uso mantêm títulos, dados e ações, sem os banners de instalação SQL,
botões de baixar SQL ou introduções explicando cada módulo. Os scripts continuam
em `supabase/` e `dist/` para instalação pelo responsável. Confirmações de ações,
erros de salvamento, instruções de campos necessários e avisos de perda de dados
continuam disponíveis. A alteração é apenas visual e não exige SQL novo.

## Refazer o quiz para estudar

Depois de concluir a tentativa oficial, o aluno pode usar **Refazer para estudar**
no cartão do quiz ou no resultado. O treino permite responder novamente e conferir
acertos, respostas corretas e explicações, com novas repetições sem limite.

O modo de treino usa apenas o gabarito que o aluno já pode consultar após a
finalização oficial. A correção é local e não chama a função de envio de tentativa,
nem salva respostas, pontuação ou progresso de treino no banco. A primeira
pontuação, as notas, o ranking e os relatórios da coordenação ficam inalterados.
Fechar ou recarregar descarta o treino. A conta precisa continuar autorizada para
consultar o quiz; vale também para quizzes encerrados com tentativa já registrada.
Não exige SQL adicional.

## Ranking na página inicial

A tela inicial do aluno mostra o ranking da semana atual da própria turma, com
os cinco primeiros e a posição do aluno quando ele estiver fora desse grupo.
Ver ranking completo abre a seção Quiz e ranking em Aprender. Voltar ao início
retoma sempre a semana atual, mesmo após consultar semanas anteriores. As regras
de pontuação, privacidade e primeira tentativa não mudam. Não exige SQL novo.
