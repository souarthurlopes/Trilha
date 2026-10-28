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
No endereço novo, entre em Configurações e informe a URL do projeto e a chave
pública Publishable ou anon. Depois entre com sua conta já autorizada.

A versão atual salva essa configuração por navegador. Definir variáveis de
ambiente no Cloudflare, sozinho, não configura o aplicativo no dispositivo.
Use Área do aluno > Copiar link de acesso no endereço novo para configurar outros
dispositivos com a mesma URL e chave pública. Senhas continuam individuais.
Não use chaves secretas ou service_role no frontend.

O endereço e o controle de visita da publicação antiga não são transferidos.
O login e as regras RLS do Supabase continuam protegendo os registros online.
Para o iPhone, abra o endereço novo no Safari e adicione-o à Tela de Início.
