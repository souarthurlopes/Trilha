# Publicar no Cloudflare

## Cloudflare Pages

Este aplicativo é estático. No painel Cloudflare:

1. Abra Workers & Pages e escolha criar uma aplicação do tipo **Pages**.
2. Conecte o GitHub e selecione **souarthurlopes/Trilha**.
3. Use as configurações:

| Campo | Valor |
| --- | --- |
| Branch de produção | `main` |
| Framework preset | `None` |
| Build command | `npm run build` |
| Build output directory | `dist` |
| Root directory | raiz do repositório |
| Node.js | `22` (também declarado em `.nvmrc`) |

4. Faça o primeiro deploy e abra o endereço gerado pelo Cloudflare.

O arquivo `dist/_headers` mantém os arquivos principais revalidáveis para que
atualizações do aplicativo e do service worker cheguem aos dispositivos.

## Se escolher Workers em vez de Pages

O `wrangler.jsonc` incluído permite publicar `dist` como assets estáticos de um
Worker, sem servidor ou funções adicionais.

- Build command: `npm run build`
- Deploy command: `npx wrangler deploy`
- Worker name: `trilha-apostolica`, conforme o `wrangler.jsonc`.

Se escolher outro nome no painel, ajuste `name` no arquivo para o mesmo nome.
O arquivo não contém credenciais nem identificador de conta Cloudflare.
Este repositório não executa um deploy por conta própria.

## Conectar o Supabase

Mantenha o projeto atual. Não é necessário rodar o SQL novamente nem criar banco.
### Conexão padrão, sem chaves por dispositivo

No projeto do aplicativo, abra **Settings → Build → Variables and secrets**
(ou a seção de variáveis de ambiente do build) e cadastre:

- `PUBLIC_SUPABASE_URL`: Project URL do mesmo projeto Supabase.
- `PUBLIC_SUPABASE_KEY`: chave pública Publishable ou anon do projeto.

Use o ambiente de **Production**. Se também quiser previews, configure os valores
para o ambiente de preview conforme a opção disponível na sua conta.

As variáveis precisam estar disponíveis no **build**, pois o aplicativo é estático.
Variáveis definidas apenas como bindings do Worker em execução não substituem
as variáveis de build. Salve e inicie um novo build/deploy.

O build `npm run build` gera a conexão padrão automaticamente. O `wrangler.jsonc`
também chama esse build ao publicar via Wrangler. O arquivo `dist/config.js`
contém apenas URL e chave pública; nenhuma senha ou chave privilegiada é aceita.
Use a Publishable ou anon; nunca service_role ou sb_secret.

Depois da publicação, o novo endereço abre diretamente no login para todos.
Cada pessoa continua usando a própria conta e os acessos concedidos pela coordenação.
Não é necessário executar SQL novamente. Se o app já estava aberto, recarregue-o
para carregar a conexão padrão.

Sem as variáveis de build, a configuração manual por navegador continua disponível.

O endereço e o controle de visita da publicação antiga não são transferidos.
O login e as regras RLS do Supabase continuam protegendo os registros online.
Para o iPhone, abra o endereço novo no Safari e adicione-o à Tela de Início.

## Cadastro autônomo dos alunos

Depois de ativar a migração de cadastro, configure uma vez no Supabase:

1. Authentication > Sign In / Providers: Allow new users to sign up ativado.
2. Mantenha a confirmação de e-mail habilitada.
3. Authentication > URL Configuration: Site URL com o endereço HTTPS real do app.
4. Inclua esse mesmo endereço nas Redirect URLs permitidas.

As pessoas usam Criar conta no próprio aplicativo. Depois da confirmação e do
primeiro login, você aprova as solicitações em Área do aluno. Não é necessário
criar cada pessoa em Authentication > Users. O primeiro responsável e eventuais
novos coordenadores continuam dependendo de autorização explícita.

## Ativar quizzes e ranking

Depois do deploy da versão que contém a aba Quizzes, execute `dist/quizzes.sql`
no SQL Editor do projeto Supabase existente (requer a área do aluno instalada).
Clique em Atualizar dados no app. Nenhuma nova variável de ambiente é necessária.
O deploy sozinho não cria tabelas no Supabase. O ranking é separado por turma e
semanal; a correção e a proteção da primeira tentativa ocorrem no banco.
