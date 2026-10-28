# Trilha Apostólica

Aplicativo web instalável (PWA) para coordenação e alunos, com a identidade visual oficial.

- Cadastro de alunos e turmas, notas e chamada por data.
- Perfis e equipe de coordenação com contas individuais.
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

Em Configurações, informe a Project URL e a chave Publishable ou anon. Nunca use
service_role ou sb_secret. A configuração atual fica salva em cada navegador;
Área do aluno > Copiar link de acesso ajuda a configurar outros dispositivos.
Senhas e registros reais dos alunos não fazem parte deste repositório.

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
