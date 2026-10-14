# Urna do grêmio estudantil

Aplicativo web para **dois computadores supervisionados**, com votos consolidados no Supabase e interface estática preparada para GitHub Pages.

## O que está implementado

- Entrada **BOA TENTATIVA!**, login por e-mail e senha validados no Supabase Auth.
- Escolha entre duas chapas com imagem, botão VOTAR, confirmação e retorno.
- Som sintetizado de confirmação e FIM por oito segundos, somente após confirmação do banco.
- No máximo duas sessões de terminal autorizadas; a mesma conta administrativa pode entrar nos dois PCs.
- Oito segundos de intervalo também no servidor, independentemente da tela.
- Recibo único por envio, persistido na aba até a confirmação, para repetir uma solicitação sem duplicar a contagem.
- `apuracao.html`: total público enquanto aberta; votos e porcentagens por chapa apenas após encerramento.
- `encerrar.html`: página sem link na urna, protegida por permissão administrativa. Abre, encerra e revoga terminais.
- Encerramento definitivo e transacional: o banco serializa votos e encerramento, bloqueando votos posteriores.
- Contadores por chapa sem identidade de aluno. Recibos não guardam a escolha. Tabelas internas não ficam acessíveis pela API pública.

**Estado da entrega:** código implementado; requer um projeto Supabase configurado e a ativação do GitHub Pages. Não existe banco de demonstração nem voto salvo somente no navegador.

## 1. Preparar o Supabase

1. Crie um projeto em https://supabase.com/dashboard. Guarde a senha do banco fora do GitHub.
2. Abra o SQL Editor e execute **uma única vez**, em um projeto novo, todo o arquivo `supabase/schema.sql`.
3. Em Authentication, desative o cadastro público de novos usuários. Não há cadastro na interface da urna.
4. Em Authentication → Users, crie seu usuário com **e-mail e senha forte**, confirmado. Use um e-mail como login; não coloque a senha no campo login. Não envie a senha pelo chat nem grave no repositório.
5. Copie o UUID do usuário e execute no SQL Editor, substituindo o valor abaixo:

```sql
insert into election_private.operators(user_id, role)
values ('UUID-DO-SEU-USUARIO', 'admin');
```

Opcionalmente crie contas de terminal com papel `terminal`, que votam mas não encerram a eleição. O administrador não precisa ativar uma sessão de terminal para acessar `encerrar.html`.

6. Copie a Project URL e a chave **publishable** (ou a antiga chave **anon**) do projeto. Edite `public/config.js`:

```js
supabaseUrl: 'https://SEU-PROJETO.supabase.co',
supabaseKey: 'SUA_CHAVE_PUBLICAVEL',
```

Esses dois valores são públicos por definição. **Nunca use secret key, service_role, senha do banco ou senha administrativa nesse arquivo.** A autorização é feita pelo banco, não pela chave pública. Consulte https://supabase.com/docs/guides/database/functions e https://supabase.com/docs/guides/database/postgres/row-level-security.

## 2. Personalizar

Em `public/config.js`, altere o nome da escola, o título da eleição e os nomes das chapas. Mantenha os identificadores A e B.

Adicione as fotos em `public/assets/` e altere `image` para os respectivos caminhos. Os SVGs incluídos são **imagens provisórias**, identificadas como tal. Não foram recebidos nomes ou fotos reais.

## 3. Publicar no GitHub Pages

1. No repositório, abra Settings → Pages.
2. Em Source, selecione **GitHub Actions**.
3. Abra Actions → Deploy GitHub Pages → Run workflow (ou envie um commit para main).
4. Espere a execução ficar verde e use a URL retornada pelo deploy. Para a configuração padrão deste repositório, a URL esperada é `https://vit0r-maker.github.io/URNA/`.

O workflow publica somente a pasta `public/`. O SQL fica como código-fonte, não é executado pelo Pages.

Páginas previstas após o deploy:

| Uso | Caminho |
| --- | --- |
| Urna com login | `/URNA/` |
| Apuração pública | `/URNA/apuracao.html` |
| Administração sem link na urna | `/URNA/encerrar.html` |

A URL administrativa pode ser descoberta no repositório público. **A proteção efetiva é a autenticação e a verificação do papel admin no servidor.**

## 4. Operar no dia

1. Configure e valide a aplicação em um **projeto Supabase de teste separado**, usando o roteiro abaixo. Só depois configure o projeto definitivo, ainda sem votos.
2. Entre em `encerrar.html` com a conta administrativa e clique **Abrir votação**.
3. Em cada computador, abra a urna, faça login e deixe a tela de escolha aberta. Use uma única aba por computador e tela cheia. Não compartilhe a senha com alunos.
4. O fiscal controla a fila e confere quem já votou na lista da escola. O sistema não cadastra alunos e **não detecta se a mesma pessoa voltou à fila**.
5. Cada confirmação mostra FIM por oito segundos; depois retorna automaticamente à escolha. Não é necessária liberação por aluno.
6. Compartilhe somente o endereço da apuração com os espectadores.
7. No fim, aguarde os últimos terminais concluírem o envio, acesse `encerrar.html` e confirme **Encerrar votação**. O banco passa a recusar novos votos imediatamente, e a página pública atualiza em até cinco segundos quando conectada.

## Falhas e troca de computador

- **Falha no envio:** use “Verificar / tentar novamente” na mesma aba. O recibo é reutilizado. Não limpe o armazenamento nem troque de aba antes de resolver uma tentativa pendente. Uma resposta perdida não significa que o banco não contou o voto.
- **Mais de dois terminais:** no painel, revogue os terminais. Nas urnas, feche as abas e abra novas abas para entrar novamente (o login é armazenado em sessionStorage). Isso bloqueia as sessões anteriores no banco.
- **Conta sem permissão:** o usuário precisa constar em `election_private.operators`. Apenas estar cadastrado no Auth não concede acesso.
- **Eleição encerrada:** não há reabertura ou exclusão de votos na interface. Uma próxima eleição requer um novo projeto/banco preparado, preservando o resultado anterior.
- **Sem internet:** o aplicativo não aceita votos offline. O fiscal deve pausar a fila.
- A sessão expira conforme a configuração do Supabase e é renovada enquanto possível. Em caso de expiração definitiva com envio pendente, o administrador deve verificar o incidente antes de liberar outra tentativa.

## Verificação

```sh
node --check public/app.js
npm install
npm test
```

Os testes automatizados executam o fluxo JavaScript com DOM/API simulados e as funções SQL em PostgreSQL embarcado (PGlite), com autenticação simulada. Cobrem permissões, dois terminais, intervalo, recibos repetidos e encerramento. Não substituem a validação do Supabase real e dos navegadores dos dois computadores.

Roteiro obrigatório no projeto de teste:

- Usuário não cadastrado como operador: login não libera votação; chamada direta de voto é recusada.
- Visitante sem login: vê apuração, mas não consegue votar ou encerrar; acesso direto às tabelas privadas é recusado.
- Conta `terminal`: vota, mas não encerra.
- Abra duas sessões e tente uma terceira: deve ser recusada.
- Vote uma vez em cada PC: total deve ser 2, sem contagem por chapa na resposta pública.
- Repita o mesmo `p_request_id`: total não muda; novo ID antes de oito segundos é recusado.
- Simule resposta perdida e tente de novo: um só voto deve ser contado.
- Encerre enquanto outro PC tenta votar: nenhum voto pode ser aceito depois da transição no banco.
- Após encerrar: percentuais corretos (inclusive 0 votos e empate); não é possível reabrir.
- Confirme imagem, som e legibilidade nos dois navegadores reais.

Esta é uma urna escolar supervisionada. A senha protege o acesso remoto; o fiscal e a lista de participação controlam um voto por aluno. Não é um sistema de identificação de eleitores ou uma urna eleitoral certificada.
