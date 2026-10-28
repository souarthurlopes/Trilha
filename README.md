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
