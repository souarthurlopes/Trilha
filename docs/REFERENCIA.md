> Conexão padrão: use PUBLIC_SUPABASE_URL e PUBLIC_SUPABASE_KEY no build.
> As referências abaixo à configuração por navegador descrevem o modo legado,
> disponível quando a publicação não tem conexão padrão. Veja CLOUDFLARE.md.

# Trilha Apostólica

Aplicativo PWA estático para a coordenação da Trilha Apostólica. Inclui turmas,
alunos, avaliações, notas de 0 a 10, chamada por data, avisos e acompanhamento.

## Abrir e instalar

Abra o endereço publicado. No iPhone, use Safari > Compartilhar > Adicionar à
Tela de Início. O site é privado para o proprietário no Sites. O login do
Supabase é uma segunda camada, independente do acesso à hospedagem.

Sem configurar Supabase, os dados ficam exclusivamente no localStorage do
navegador. Use Configurações > Exportar cópia antes de trocar de dispositivo.
A gravação online exige conexão; não há fila de sincronização offline.

## Conectar ao Supabase

1. Crie um projeto Supabase próprio.
2. Execute `supabase/schema.sql` no SQL Editor.
3. Em Authentication > Users, crie o coordenador com e-mail confirmado.
4. Execute a autorização usando o UUID real:
   `insert into public.school_coordinators(user_id) values ('UUID-REAL');`
5. Desative novos cadastros no painel de Authentication.
6. No aplicativo, Configurações, preencha a URL HTTPS e a chave pública
   publishable ou anon. Nunca use service_role ou sb_secret.
7. Entre com o e-mail e a senha do coordenador.
8. Se havia dados locais, importe a cópia JSON após o login. O aplicativo
   não migra registros locais automaticamente.

## Perfis e coordenação compartilhada

A aba Perfil permite salvar nome, foto, telefone e responsabilidade. O e-mail
é o da conta de login. Fotos são reduzidas para 256 × 256 e armazenadas na tabela
privada school_profiles, sem incluir imagens nos tokens de autenticação.

Para atualizar um banco já configurado, execute `supabase/profiles-team.sql`.
O `schema.sql` completo já inclui essa atualização para projetos novos.
A migração é transacional, pode ser repetida e preserva os dados existentes.
Sem aplicá-la, o aplicativo mantém as notas e os dados antigos funcionando e
mostra as instruções na aba Perfil. Perfis locais ficam só no navegador.

O responsável principal pode adicionar e remover coordenadores por e-mail em
Perfil > Equipe de coordenação. As contas precisam ter sido criadas e confirmadas
em Authentication > Users. A operação não envia e-mails. Os novos membros não
precisam ser incluídos em school_coordinators: school_team_members vincula cada
conta aos dados do responsável, com as políticas de acesso necessárias.

Todos os coordenadores da equipe editam o mesmo documento de turmas, alunos,
notas, chamadas e avisos. Somente o responsável gerencia os acessos. Quem participa
de mais de uma equipe pode selecionar o espaço na aba Perfil. Edições concorrentes
são protegidas pela revisão; use Atualizar dados antes de editar dados desatualizados.
A revogação impede novas leituras e gravações, sem apagar a conta ou o histórico.

Cada dispositivo precisa da mesma URL e chave pública do projeto. O site continua
privado no Sites; a autorização no Supabase não libera automaticamente a visita
ao endereço. O proprietário precisa conceder acesso aos outros coordenadores
na hospedagem. Não há liberação pública nem envio automático de convites.

Esta primeira versão usa um documento JSONB por equipe com referências por
UUID, validação no banco e concorrência otimista. A média é simples: notas com
o mesmo peso, ignorando avaliações sem nota. Zero é válido. Faltas justificadas
ficam no histórico e fora do denominador da frequência. Atividades semanais
opcionais não fazem parte da versão inicial e não devem alterar a média.

## Desenvolvimento

`npm ci` e `npm run build` recompilam a biblioteca oficial do Supabase, incluída
localmente em `dist/supabase.js`. `npm run check` verifica a sintaxe. A aplicação
está em `dist/app.js` e `dist/style.css`, sem compilação adicional.

Para pré-visualizar: `python -m http.server 4173 --directory dist`.
O esquema SQL também pode ser baixado nas configurações do aplicativo.

A identidade visual usa a logo oficial enviada pelo usuário, preservada em assets/logo-original.jpg, com tema em preto, branco e cinza. Os SVGs de marca enquadram a imagem original sem redesenhar o símbolo ou a tipografia.

## Área do aluno

A atualização `supabase/student-area.sql` habilita contas individuais de alunos,
textos e links de materiais, atividades opcionais e respostas. Execute-a após a
migração de perfis/equipe. O esquema completo já inclui as três etapas.

A coordenação usa Área do aluno para publicar conteúdos por turma, manter
rascunhos, consultar respostas e abrir uma prévia. A prévia não permite envios.
Crie uma conta confirmada em Authentication > Users e vincule-a ao aluno por
email. Nunca autorize alunos em school_coordinators ou school_team_members.

O login detecta o perfil a partir das autorizações do banco. Para alunos, não
consulta o documento completo da escola: school_student_portals retorna somente
os registros do próprio aluno. Notas e presença são somente leitura; observações
internas do cadastro não são retornadas. O banco limita materiais à turma atual
e exclui rascunhos. Alunos podem editar apenas suas respostas e seu perfil.

Atividades são opcionais, não possuem pontuação e não modificam as avaliações.
A data é uma sugestão, não um bloqueio de entrega. Materiais podem conter texto
e links HTTPS para PDF, vídeos e outras referências; não há upload de arquivos.
As respostas são pessoais e ficam visíveis à coordenação, com controle de acesso
no banco. Remover o vínculo ou o aluno do documento revoga as próximas consultas.

O botão Copiar link de acesso inclui apenas URL e chave pública na âncora da URL,
para configurar outro dispositivo. Chaves secretas são rejeitadas. Se já houver
outro projeto no navegador, a troca requer confirmação. O link não substitui o
login nem a autorização de visita à hospedagem privada. Não envia mensagens.

A cópia JSON dos registros escolares mantém o escopo anterior e não inclui
materiais, respostas ou vínculos de autenticação. Esses dados permanecem nas
respectivas tabelas do Supabase. No modo local, conteúdos ficam no mesmo navegador.

Validação: `node qa/student-database.mjs` exercita migração, RLS, isolamento,
revogação e preservação das notas. `qa/student-browser.cjs` cobre publicação,
prévia, login do aluno, respostas e interface responsiva com APIs simuladas.

## Financeiro individual dos alunos

A aba Financeiro da coordenação cadastra cobranças individuais com descrição,
valor em reais e vencimento. O aluno consulta situação, saldo em aberto,
pendências, próxima data e histórico de pagamentos. Não há processamento de
pagamentos, boletos, Pix automático, recorrência nem pagamentos parciais.
A coordenação confirma manualmente o valor integral e informa data e forma de
pagamento. As cobranças não alteram notas, presenças ou atividades.

O download `dist/finance.sql` reúne a área do aluno e a migração financeira em
uma transação, permitindo atualizar um banco que já tenha perfis/equipe mesmo
sem ter executado a etapa de alunos. `supabase/finance.sql` é apenas a etapa
financeira. O schema completo inclui tudo para projetos novos. A aplicação
continua funcionando antes da migração e apresenta instruções de ativação.

Valores são inteiros em centavos; a entrada aceita 120,00, 120.00 e 1.234,56.
O dia de referência é America/Sao_Paulo. Vence hoje não significa atraso.
A próxima data é o primeiro vencimento em aberto a partir de hoje, sem confundir
pendências antigas com próximas cobranças. Canceladas não contam no saldo.
Sem cobranças ativas, a interface informa isso em vez de afirmar que está em dia.

RLS permite alterações somente à coordenação e leitura individual aos alunos
vinculados, inclusive após troca de turma. Remover o vínculo ou excluir o aluno
do documento escolar revoga a leitura. O nome no lançamento é preservado para
manter o histórico mesmo se o cadastro for removido posteriormente. A interface
impede excluir um aluno enquanto há cobranças em aberto carregadas.

Pagamentos confirmados precisam ser reabertos para correção; canceladas ficam
imutáveis no histórico. Não há exclusão direta pelo aplicativo. Atualizações
usam row_version para rejeitar gravações concorrentes. O banco registra todas
as alterações em school_finance_audit, com autor e valores anteriores/atuais,
visíveis somente à coordenação. O histórico pode ser consultado em cada cobrança.

As cobranças têm exportação CSV própria; o backup escolar JSON não as inclui.
O modo local guarda as cobranças neste navegador, sem histórico de auditoria do
banco. A prévia do aluno também apresenta o financeiro filtrado pelo cadastro.

Validação: `qa/finance-utils.mjs` cobre centavos, datas e totais;
`qa/finance-database.mjs` cobre migrações, RLS, auditoria, concorrência e limites;
`qa/finance-browser.cjs` cobre os registros, confirmação e consulta na interface.
