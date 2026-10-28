# Implantação

## Manter o banco atual

O GitHub guarda o código; o Supabase mantém os registros online. Use o mesmo projeto
Supabase e as contas existentes. Não apague tabelas nem recrie o banco para trocar
a hospedagem. O login e os vínculos dos alunos continuam no projeto original.

Dados salvos apenas no navegador não migram com o código ou com o domínio.
Antes da troca, exporte os registros escolares e o CSV financeiro que estiverem
locais. O backup JSON escolar não inclui materiais, respostas, financeiro ou contas.
Conteúdos locais permanecem no navegador antigo; os conteúdos já no Supabase
continuam disponíveis ao conectar o mesmo banco no novo endereço.

## Publicar o aplicativo

Conecte o repositório a uma hospedagem estática usando Node 22 ou superior,
instalação `npm ci`, build `npm run build` e saída `dist`.
Não execute SQLs automaticamente na etapa de build. Use HTTPS e evite cache
prolongado de `index.html` e `sw.js`.
Não há publicação automática no GitHub Pages, Netlify ou Vercel neste repositório.

Configure PUBLIC_SUPABASE_URL e PUBLIC_SUPABASE_KEY nas variáveis de build da
hospedagem e publique novamente. O endereço novo abrirá direto no login em todos
os dispositivos. Entre com a conta existente; não são necessárias chaves por usuário.
Veja docs/CLOUDFLARE.md para o caminho das variáveis no Cloudflare. Sem variáveis
de build, continua disponível a configuração manual por navegador.

A restrição de visita da publicação antiga no Sites não acompanha o código.
Configure o acesso da hospedagem nova conforme a plataforma escolhida.
As políticas RLS do Supabase continuam limitando os dados por usuário.
O login atual de senha usa diretamente a API do Supabase; se adicionar OAuth,
links mágicos ou recuperação por e-mail, configure também as URLs de retorno.

## Supabase novo

Somente se precisar realmente de outro banco:

1. Crie o projeto e execute `supabase/schema.sql` no SQL Editor.
2. Em Authentication > Users, crie o responsável com e-mail confirmado.
3. Autorize o UUID real:

```sql
insert into public.school_coordinators(user_id)
values ('COLE-O-UUID-REAL-AQUI')
on conflict (user_id) do nothing;
```

4. Desative novos cadastros públicos em Authentication.
5. Configure URL e chave pública no aplicativo e entre com esse usuário.
6. Adicione a equipe pela aba Perfil e vincule alunos em Área do aluno.

Alunos não devem entrar em school_coordinators nem school_team_members.
O esquema completo reúne todas as etapas para um banco novo; os arquivos de
atualização individuais dependem das etapas anteriores descritas em cada arquivo.

## Instalar no iPhone

Abra o endereço novo no Safari e use Compartilhar > Adicionar à Tela de Início.
Um ícone instalado do domínio antigo continuará abrindo o domínio antigo.
Antes de divulgar o novo endereço, confira contas reais de coordenador e aluno,
notas, presença, atividades e financeiro. Testes automáticos usam dados fictícios.
