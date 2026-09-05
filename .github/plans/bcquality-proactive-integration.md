# BCQuality da reattivo a proattivo — analisi, rischi, piano

**Stato**: proposta · **Owner**: R&D · **Data**: 2026-09-05
**Repo coinvolti**: `DSC-Group-Srl/ALDC-AL-Development-Collection` (fork, sorgente del plugin) ·
`DSC-Group-Srl/dscgroup-bc-nav-agentic-dev` (marketplace)
**Riferimento upstream**: `microsoft/BCQuality` @ `1a5afdc` (2026-09-03)

---

## 1. In breve

Oggi BCQuality entra nel nostro flusso **solo dopo** che il codice è stato scritto. Chi
scrive il codice segue un secondo regolamento, il nostro, che in almeno cinque punti dice
il contrario di BCQuality. La review non misura la qualità: misura la distanza fra i due
regolamenti.

La proposta è invertire l'ordine — stessa knowledge in implementazione e in review — e
cambiare di conseguenza il mestiere della review, che smette di cercare violazioni e passa
a cercare **ciò che la knowledge non copre**.

Tre decisioni sul tavolo:

| | Decisione | Raccomandazione |
|---|---|---|
| **A** | Rimuovere la catena Copilot/VS Code dalla fork | **Sì**, ma vincolata a una scelta sul sync upstream |
| **B** | Portare BCQuality in fase di implementazione | **Sì**, per fasi, con le mitigazioni della §5 |
| **C** | Valorizzare il layer `/custom/` DSC | **Rinviata** — cartella preparata, contenuti a un'attività dedicata |

---

## 2. La situazione di oggi

### 2.1 ALDC contiene due catene di distribuzione indipendenti

La fork non è un repo con del codice morto: è un repo con **due prodotti** che condividono
la storia ma non i file.

```
                    ALDC-AL-Development-Collection (fork)
                                  │
        ┌─────────────────────────┴──────────────────────────┐
        │                                                    │
   CATENA A — Copilot / VS Code                    CATENA B — Claude Code
   (eredità upstream, non nostra)                  (nostra, l'unica che usiamo)
        │                                                    │
   agents/ skills/ instructions/ prompts/            claude-plugin/
        │  (sorgente)                                    │  (sorgente, scritto a mano)
        ├──> scripts/sync-foundation.js                  ├──> scripts/sync-claude-workspace.js
        │    └──> packages/foundation/ ──> VSIX          │    └──> .claude/  (dogfooding)
        ├──> package.json files[] ──> pacchetto npm      │
        ├──> collections/*.collection.yml                └──> GH Action nel marketplace
        ├──> aldc.yaml (required.*) ──> aldc-validate         └──> plugins/bc-dev/
        ├──> aldc.code-workspace (multi-root BCQuality)
        ├──> .github/copilot-instructions.md
        └──> mkdocs.yml + docs/ (7,9 MB) ──> GitHub Pages
```

Le due catene **non si generano a vicenda**. `claude-plugin/` non deriva da `agents/`, e
`agents/` non deriva da `claude-plugin/`. Sono due copie parallele delle stesse idee, che
hanno divergito. È la causa strutturale dei conflitti della §2.4.

### 2.2 Chi lavora su cosa — i numeri

| Albero | File | Commit ultimi 6 mesi | Autori |
|---|---:|---:|---|
| `claude-plugin/` | 107 | **46** | Tommaso 40 · Javier 5 · Dario 1 |
| `agents/ skills/ instructions/ prompts/ collections/ packages/` | 142 | **14** | **Javier 14 · DSC 0** |

Zero commit DSC sulla catena A in sei mesi. Tutti e 14 sono arrivati dal sync upstream.
`claude-plugin/` è ormai **avanti**: 3 agenti in più (`al-documentation-*`) e 7 skill in
più (`skill-aldoc`, `skill-changelog`, `skill-mcp`, `skill-al-mcp-workspace`,
`skill-developer-docfx`, `skill-functional-docfx`, `skill-functional-docx`).

### 2.3 Stato della CI

| Workflow | Trigger | Nota |
|---|---|---|
| `sync-upstream.yml` | **cron settimanale** (lun 04:00 UTC) | **ATTIVO** — tira da `javiarmesto/AL-Development-Collection-for-GitHub-Copilot` |
| `validate.yml` | dispatch | disabilitato ("upstream workflow") |
| `aldc-validate.yml` | dispatch | disabilitato |
| `lint.yml` | dispatch | disabilitato |
| `docs.yml` | dispatch | disabilitato |
| `release.yml` | dispatch | disabilitato |
| `bcquality-evidence.yaml` | dispatch | disabilitato |

Sei workflow su sette sono già stati neutralizzati. La catena A **non è già più validata**:
è codice non testato che continua ad arrivare.

### 2.4 Come arriva al marketplace

`bc-dev-upstream-drift.yml` nel repo marketplace copia `claude-plugin/` → `plugins/bc-dev/`,
apre PR su branch `bc`, reviewer `ci-cd-admins`. Due precisazioni rispetto a come lo
descriviamo di solito:

- **non è "ad ogni push"**: è un cron giornaliero alle 05:00 UTC (più `workflow_dispatch`).
  Lo scarto medio fra un commit e la sua PR di sync è ~12 ore;
- **non cancella mai**. Il commento nel workflow è esplicito: *"Files that only exist in
  plugins/bc-dev … are left alone; nothing is deleted."*

Stato di salute verificato oggi: **0 file con contenuto divergente**, **4 file orfani** in
`plugins/bc-dev/skills/skill-extension-manifest/` — residuo di una rinomina a monte che il
sync non ha potuto propagare. Il pipeline funziona; la sua unica falla è strutturale ed è
esattamente quella che ci morderà se facciamo pulizia (→ R6).

### 2.5 Dove BCQuality tocca il flusso, oggi

Conteggio delle occorrenze `bcquality` per agente in `claude-plugin/agents/`:

| Agente | Occorrenze | Fase | Ruolo |
|---|---:|---|---|
| `al-review-subagent` | 10 | **post-implementazione** | consuma la decisione, esegue il dispatch, produce findings citati |
| `dredd` | 9 | **post-implementazione** | audit indipendente on-demand, stesso corpus |
| `al-conductor` | 6 | orchestrazione | risolve `enabled` una volta, costruisce il task-context, mostra la riga `🔎` |
| `al-triage` | 3 | reattivo | diagnosi da sintomo |
| `al-architect` | **0** | pre-implementazione | — |
| `al-planning-subagent` | **0** | pre-implementazione | — |
| `al-implement-subagent` | **0** | **implementazione** | — |
| `al-developer` | **0** | implementazione | — |

Il dato è netto: **nessuno degli agenti che scrivono codice ha mai visto BCQuality.**

### 2.6 Cosa c'è davvero in BCQuality

| | Quantità |
|---|---:|
| Knowledge file (`.md`) | **300** |
| Sample AL good/bad (`.al`) | **485** |
| Action skill totali | 17 |
| di cui `review/` | **17** |
| di cui authoring/generazione | **0** |

Distribuzione per dominio: performance 65 · style 35 · ui 32 · security 25 · upgrade 22 ·
agents 20 (community) · privacy 18 · data-modeling 12 · web-services 9 ·
breaking-changes 9 · error-handling 8 · telemetry 7 · testing 6 · interfaces 5 ·
appsource 4 · query 2.

**Non esiste una skill proattiva.** La knowledge però è dichiaratamente dual-use: il test
di ammissione nel README è *"would a modern LLM **reviewing or generating** BC code make a
mistake this file would have prevented?"*. La skill di authoring dobbiamo scriverla noi,
nel layer `/custom/`, che esiste apposta.

Novità dall'ultima volta che abbiamo guardato: BCQuality si installa anche **come plugin
Claude Code** (`.claude-plugin/marketplace.json`, `plugin.json` v0.2.0, skill host-native
`skills/al-code-review/SKILL.md`).

### 2.7 I conflitti attivi — la fotografia scomoda

| # | Nostra regola | BCQuality | Effetto |
|---|---|---|---|
| 1 | `rules-floor-cheatsheet.md:13` e `al-naming-conventions.instructions.md:14` — *"Event subscriber params: descriptive, never bare `Rec`"* | `style/event-subscriber-param-names-match-publisher.md` — i nomi **devono** essere copiati verbatim dal publisher, `Rec`/`xRec`/`Sender` inclusi; *"Style rules … descriptive names — do not apply to subscriber parameters"* | Generiamo codice **che non binda**. Quel file ha `false-positive` fra i keyword: esiste per impedire quello che noi ordiniamo |
| 2 | `al-performance.instructions.md:11` — *"Order matters: `SetLoadFields` → `SetRange` → `Find`"* | `performance/use-setloadfields-for-partial-records.md` — la posizione *"does not change the projection"*, va messo **dopo** i filtri, *"never a performance defect"* | Contraddiciamo MS **e noi stessi**: `rules-floor-cheatsheet.md:15` dice l'opposto del nostro file instructions |
| 3 | `al-code-style.instructions.md:10` — *"Indentation: 2 spaces"* | — | `rules-floor-cheatsheet.md:11` dice *"4-space indent"*. Due artefatti ALDC, regole opposte |
| 4 | `al-error-handling.instructions.md:10` — *"TryFunction mandatory … o needs rollback"* | — | `rules-floor-cheatsheet.md:17` dice *"never around logic that writes"*. Opposti |
| 5 | `al-testing.instructions.md:13` — *"`Codeunit Assert`"* | — | `al-implement-subagent` dichiara che è **AL0185, WILL FAIL**. Il file di regole insegna un errore di compilazione |

Tre di questi cinque (3, 4, 5) sono conflitti **interni**, fra catena A e catena B. Si
risolvono da soli eliminando la catena A.

### 2.8 Il pilot non esiste — e non è "stale", è inoperante per costruzione

`docs/templates/bcquality-task-context.md` (spedito nel plugin) dichiara che la fonte di
verità del pilot è `aldc.yaml → external.bcquality.pilotSkills`, e che `disabled-skills`
deve disabilitare le leaf fuori pilot.

Solo che **`aldc.yaml` non esiste nei progetti dei nostri utenti**. `/aldc:al-initialize`
copia esclusivamente `rules-templates/*.md` in `.claude/rules/` — zero occorrenze di
`aldc.yaml` nel comando. Il file vive solo nel repo ALDC, dove nessun progetto AL lo vede.

Conseguenze, tutte già in produzione oggi:

| Campo | Valore atteso | Valore reale nel plugin |
|---|---|---|
| `pilotSkills` | performance, security, style | **undefined** → `disabled-skills` vuota → **tutte le 17 leaf girano, sempre** |
| `pinnedCommit` | SHA fisso per run riproducibili | **vuoto** → seguiamo sempre `main` di BCQuality, **nessun pin** |
| `enabled` | `auto \| true \| false` | default `auto` dall'hook — questo funziona |

Due letture, entrambe utili:

- **Buona notizia per il piano**: stiamo già pagando il costo delle 17 leaf in review. Il
  passaggio proposto non aggiunge costo di corpus, sposta solo *quando* lo paghiamo.
- **Cattiva notizia**: `al-review-subagent` calcola il "native residual" (A/C/F/G vs A–G)
  partendo dal presupposto che siano attive 3 leaf. Ragiona su un mondo che non esiste, e
  nessuna run è riproducibile perché non c'è pin.

### 2.9 Copertura: il divario

| | Regole | Domini governati in implementazione |
|---|---:|---|
| Noi, oggi (`rules-templates/`) | ~35 | foundational, style, naming, performance, error-handling, events, testing |
| BCQuality | 300 | i 7 sopra **+** privacy, upgrade, breaking-changes, ui, data-modeling, web-services, interfaces, telemetry, appsource, query, agents |

Dieci domini arrivano da noi solo in review, e solo se la leaf è accesa.

---

## 3. Decisione A — rimuovere la catena Copilot

### 3.1 Cosa si rimuove e cosa resta

| Rimuovere | Perché | Tenere | Perché |
|---|---|---|---|
| `agents/` `skills/` `instructions/` `prompts/` | doppioni divergenti di `claude-plugin/`, 0 commit DSC | `claude-plugin/**` | il prodotto |
| `packages/foundation/` | build VSIX che non pubblichiamo | `scripts/sync-claude-workspace.js` | genera `.claude/` per il dogfooding |
| `collections/` | formato Copilot collection | `tools/bcquality/` | install + `validate_evidence.py` |
| `scripts/sync-foundation.js`, `install.js`, `check-conformance.js`, `validate-al-collection.js`, `test-local-install.js` | servono solo alla catena A | `CLAUDE.md`, `README.md`, `CHANGELOG.md` | identità del repo |
| `tools/aldc-validate/`, `.github/actions/aldc-validate/` | valida la catena A | `.github/workflows/sync-upstream.yml` **riscritto** | vedi §3.4, opzione A2 |
| **`aldc.yaml` (tutto)** | `required.*` è catena A; `external.bcquality` viene letto da un `aldc.yaml` nel **progetto AL dell'utente**, che non esiste mai (§2.8). *Prerequisito: spostare url/ref/pinnedCommit nei default dell'hook* | `.github/plans/` | convenzione ALDC viva |
| `aldc.code-workspace` | multi-root VS Code per il clone sibling, superato dalla cache user-scope dell'hook | `docs/framework/ALDC-Core-Spec-v1.2.md` | importato da `CLAUDE.md` |
| `.github/copilot-instructions.md`, `instructions/copilot-instructions.md` | Copilot | `docs/templates/` | referenziati dagli agenti |
| `mkdocs.yml` + il grosso di `docs/` (7,9 MB) | sito Pages non pubblicato | `bc-dev` sync (nel marketplace) | il canale di distribuzione |
| `archive/v2.11.0/` | archeologia | | |
| `package.json` / `package-lock.json` (npm publish) | non pubblichiamo su npm | | |
| 6 workflow già disabilitati | codice morto dichiarato | | |

Ordine di grandezza: **~9 MB e ~300 file in meno**, la fork diventa "il sorgente del plugin
Claude" e basta.

### 3.2 Benefici

| | Beneficio | Peso |
|---|---|---|
| A-B1 | Spariscono i conflitti 3, 4, 5 della §2.7 — sono conflitti *fra le due catene* | **alto** |
| A-B2 | Un solo posto dove cambiare una regola. Oggi chi modifica `instructions/` crede di aver cambiato il comportamento e non ha cambiato niente | **alto** |
| A-B3 | Il repo diventa leggibile: chi entra capisce in 2 minuti cosa è il prodotto | medio |
| A-B4 | Meno superficie da mantenere allineata quando BCQuality cambia | medio |
| A-B5 | Il `git log` torna informativo (oggi metà dei commit sono rumore upstream) | basso |

### 3.3 Rischi e mitigazioni

| # | Rischio | P × I | Mitigazione |
|---|---|---|---|
| **R6** | **Il sync non cancella.** Se rimuoviamo file dentro `claude-plugin/`, restano per sempre in `plugins/bc-dev/` — già successo: 4 orfani `skill-extension-manifest` | **alta × alto** | Una PR manuale di pulizia su branch `bc`. **In più**: aggiungere al sync uno step di *reconcile* che cancella in `$TARGET_PATH` i file assenti a monte, escludendo una allowlist di file propri di bc-dev (`.lsp.json`, `docs/`, `tools/rules`). Va fatto **prima** di qualsiasi rimozione |
| **R7** | **Rottura della fork relationship.** `sync-upstream.yml` è attivo. Se cancelliamo gli alberi e lasciamo il cron, ogni commit upstream genera conflitti di merge a vita | alta × alto | Vedi §3.4 — è una scelta esplicita, non un effetto collaterale |
| R11 | Qualcosa in `claude-plugin/` referenzia un path della catena A | **bassa × basso** — *verificato* | Grep eseguito su `claude-plugin/**`: **zero** riferimenti a `instructions/`, `prompts/`, `packages/`, `collections/`. L'unico accoppiamento è `aldc.yaml`, e solo come **override opzionale per-progetto** (hook, template task-context, README) — l'hook ha già tutti i default cablati. Il plugin è **già disaccoppiato**. Va solo ripulito il riferimento a `pilotSkills` insieme a R8 |
| R12 | Perdiamo la storia dei file rimossi | bassa × basso | Non la perdiamo: è un `git rm`, la storia resta. Nessun archivio necessario |
| R13 | Un domani decidiamo di pubblicare per Copilot | bassa × medio | Ripristinabile da git. E BCQuality copre già Copilot per conto suo (`copilot plugin install microsoft/BCQuality`) |

### 3.4 Il nodo vero: teniamo il sync upstream?

Non è scontato come sembra. Upstream ha contribuito **5 commit su `claude-plugin/`** negli
ultimi 6 mesi e ha branch attivi in quella direzione (`claude/claude-plugin-extraction-plan`,
`claude/bcquality-enabled`). Tagliare il cordone costa qualcosa.

| Opzione | Cosa comporta | Quando ha senso |
|---|---|---|
| **A1 — Taglio netto** · disabilitare `sync-upstream.yml`, rimuovere tutto | ALDC diventa un monorepo Claude-only. Zero conflitti, zero rumore. Perdiamo i ~5 commit/anno upstream su `claude-plugin/` | Se consideriamo la nostra divergenza ormai irreversibile |
| **A2 — Sync a percorso filtrato** *(raccomandata)* · il cron pesca da upstream **solo** `claude-plugin/**`, come fa già il nostro sync verso il marketplace; il resto viene rimosso | Teniamo il valore upstream, eliminiamo il rumore. Costo: ~30 righe di workflow da riscrivere | Sempre, se il contributo upstream su `claude-plugin/` continua |
| A3 — Status quo | Nessun lavoro, i conflitti restano | Solo se rinviamo tutto |

**Raccomandazione: A2.** È l'unica che rimuove i doppioni senza rinunciare a upstream, e
riusa un pattern che già sappiamo far funzionare.

---

## 4. Decisione B — BCQuality in implementazione

### 4.1 Benefici

| # | Beneficio | Evidenza |
|---|---|---|
| B1 | **Fonte unica.** Spariscono i conflitti 1 e 2 della §2.7 — quelli con Microsoft, che la sola pulizia non risolve | §2.7 |
| B2 | **Copertura ×8.** Da ~35 regole a 300 knowledge in implementazione, con 485 sample AL good/bad | §2.9 |
| B3 | **Review mirata.** Non più "hai violato X" (che l'implementer non poteva sapere) ma "X non è coperto da nessuna knowledge" | §5 |
| B4 | **Meno rework.** I falsi positivi da conflitto di regolamento smettono di generare cicli di revisione | conflitti 1-2 |
| B5 | **Manutenzione esternalizzata.** Microsoft mantiene 300 file (release ~mensile) al posto nostro. Noi manteniamo solo `/custom/` | README BCQuality |
| B6 | **Le nostre regole diventano citabili.** Un `file:line` con un path di knowledge è verificabile; una riga di prosa iniettata inline no | §6 |
| B7 | **Onboarding.** Un nuovo sviluppatore legge un articolo con sample good/bad, non una riga di cheat sheet | 485 sample |

### 4.2 Rischi e mitigazioni

| # | Rischio | P × I | Mitigazione |
|---|---|---|---|
| **R1** | **Correlazione dei punti ciechi.** Implementer e reviewer pescano dallo stesso corpus: la review diventa un controllo di consistenza, non una misura indipendente. Il recall scende alla copertura del corpus | **alta × alto** | **(a)** Il pass **agent findings** di BCQuality è già la valvola progettata per questo (`references: []`, `from-sub-skill: "agent"`, `confidence ≤ medium`, severity capped a `minor`): renderlo **obbligatorio e in testa al report**, non in nota. **(b)** Dredd cambia scope (→ §5.6): smette di rifare lo stesso diff con lo stesso corpus. **(c)** Metrica `independence-ratio` monitorata (→ §7.3) |
| **R2** | **Anchoring.** Il reviewer verifica *che* la regola sia stata applicata invece di chiedersi *se* fosse quella giusta. Ce l'abbiamo già cablato: `skills-compliance[]` con `↗bcq` e *"do not load the ALDC skill — defer to its finding"* | media × alto | `skills-compliance` **degradato da gate a telemetria**. La review giudica l'artefatto, mai l'autodichiarazione dell'implementer — è già la regola di Dredd, va estesa alla review di fase |
| **R3** | **Automation bias.** "Review verde = certificato Microsoft". BCQuality è dichiaratamente **rimediale**: un file esiste solo dove un LLM sbaglierebbe. Non è uno standard di completezza | media × medio | Frase fissa nel template di report: *"BCQuality è un corpus rimediale, non una checklist di completezza: verde significa nessuna regola nota violata, non codice corretto."* Da scrivere, non da inferire |
| **R4** | **Inflazione di contesto e costo token.** Un retrieval di knowledge per fase, su 300 articoli | media × medio | **(a)** `knowledge-index.json` (già in BCQuality, rigenerato da `Build-KnowledgeIndex.ps1` allo step Preparation di Entry) — discovery senza aprire i file. **(b)** `goal` scopato ai domini della fase, mai "tutto". **(c)** Il worklist prescrittivo lo costruisce il **conductor una volta**, non ogni subagente |
| **R5** | **Drift upstream.** 300 file che cambiano ~mensilmente sotto di noi; una regola può cambiare fra l'implementazione e la review. **Oggi non abbiamo alcun pin** (§2.8): seguiamo `main` | **alta × medio** | Spostare `url`/`ref`/`pinnedCommit` dai default di `aldc.yaml` a **default dell'hook**, che è l'unico artefatto che i progetti vedono davvero. Pin rivisto a ogni release BCQuality, non a ogni run; il `sha` è già registrato nel report |
| **R8** | **Il pilot non esiste** (§2.8) — `aldc.yaml` non arriva mai nei progetti, quindi `disabled-skills` è sempre vuota e tutte le 17 leaf girano, mentre la review ragiona su 3 | **certa × medio** | **Abolire il pilot** e dichiarare le 17 leaf attive: è già la realtà, e allinea il ragionamento del native residual ai fatti. In alternativa, spostare `pilotSkills` in un file che il plugin installa davvero. La prima opzione è più onesta e costa meno |
| **R9** | **`/custom/` diventa il nuovo posto dove le regole divergono** — riproduciamo il problema di oggi un livello più in là | media × alto | Regola scritta nel README del layer: *una regola vive in esattamente un posto.* Ogni regola promossa a knowledge **esce** da `rules-templates/` nello stesso commit. Duplicare una regola Microsoft in `/custom/` è vietato: se la nostra e la loro divergono, quasi sempre va tolta la nostra |
| R10 | **Perdita di indipendenza di Dredd** — se gira sullo stesso corpus e sullo stesso diff, non aggiunge informazione | media × medio | Scope di default a modulo/codebase e su codice **non** prodotto nella sessione corrente. Campo `audit.baseline: aligned \| unaligned` per non confrontare per sbaglio numeri incomparabili |
| R14 | **Regressione silenziosa dell'implementer**: il worklist prescrittivo satura il contesto e l'implementer smette di applicare le skill procedurali ALDC | bassa × medio | Le skill ALDC restano su ciò che BCQuality **non** copre (procedura: come si struttura un test, una PromptDialog, un permission set). La riga simbolica continua a tracciarle separatamente |

### 4.3 Il bias che *rimuoviamo*

Va detto perché altrimenti il bilancio sembra tutto in perdita. Oggi abbiamo un bias
peggiore di tutti quelli in tabella: **conflitto di fonte**. L'implementer ottimizza per il
regolamento A, il reviewer valuta contro il regolamento B, e il delta viene riportato come
difetto. Produce falsi positivi documentati (§2.7 casi 1-2), rework, e soprattutto insegna
al team a ignorare i findings.

Netto: unificare conviene, **a condizione** di tenere R1(a), R1(b) e R2. Senza quelle tre
mitigazioni stiamo solo comprando consistenza al prezzo del recall.

---

## 5. Flussi logici per agente — oggi → domani

Notazione: **[+]** nuovo · **[~]** modificato · **[-]** rimosso.

### 5.1 `al-architect`

| | Oggi | Domani |
|---|---|---|
| BCQuality | nessuno | **[+]** consultazione read-only sui domini di design |
| Flusso | requisito → analisi → `architecture.md` | requisito → **[+]** Entry con `goal: "design AL solution"` e `inputs-available: [spec]` → worklist su `data-modeling`, `interfaces`, `events`, `upgrade`, `breaking-changes`, `appsource` → analisi → `architecture.md` |
| Output | `> **Skills applied**: skill-api, skill-events` | **[~]** `> **Skills applied**: …` **[+]** `> **Knowledge applied**: bcq:data-modeling(3) · bcq:events(2) · bcq:upgrade(1)` **[+]** sezione `## Vincoli di qualità noti` — elenco dei path di knowledge che l'implementazione dovrà rispettare, con il perché |

*Razionale*: gli errori di data modeling e di compatibilità upgrade sono i più costosi da
correggere a valle. Intercettarli in architettura vale più che intercettarli in review.

### 5.2 `al-planning-subagent`

| | Oggi | Domani |
|---|---|---|
| BCQuality | nessuno | **[+]** costruisce il **knowledge worklist** per i domini che le fasi toccheranno |
| Flusso | ricerca contesto → findings strutturati al conductor | ricerca contesto → **[+]** worklist BCQuality per fase → findings |
| Output | findings strutturati | **[+]** blocco `knowledge-worklist: [{phase, domain, paths[]}]` — il conductor lo passa all'implementer senza ricalcolarlo |

*Razionale*: il retrieval si paga **una volta**, in planning, non a ogni fase (mitiga R4c).

### 5.3 `al-conductor`

| | Oggi | Domani |
|---|---|---|
| Risoluzione BCQuality | una volta per **run**, propagata ai subagenti | **[~]** una volta per **sessione**; invariato il resto |
| Task-context | **uno**, `goal: "review AL source changes"`, costruito prima della review | **[~]** **due**: `goal: "implement AL"` verso l'implementer (dal worklist del planning) e `goal: "review AL source changes"` verso la review |
| `disabled-skills` | denylist hardcoded nel template, stale | **[~]** derivata da `aldc.yaml → pilotSkills`, o pilot abolito (R8) |
| Checkpoint | riga `🔎 {🟢 BCQuality <sha>} · 📐 instr ✓ · 🧠 {skill·tag}` | **[~]** `🔎 {🟢 BCQuality <sha>} · 📚 bcq {P prescritte / C citate / D deviate} · 📐 instr ✓ · 🧠 {skill·tag}` |
| `phase-complete.md` | Skills Applied table | **[+]** tabella **Knowledge: prescritta vs citata** — la metrica di bias, leggibile a colpo d'occhio |

*Razionale*: il conductor è l'unico che vede entrambi i lati. È il posto giusto dove
misurare la divergenza fra "cosa abbiamo detto all'implementer" e "cosa ha trovato la
review".

### 5.4 `al-implement-subagent`

| | Oggi | Domani |
|---|---|---|
| Fonte delle regole | micro-regole inline dal conductor + skill ALDC on demand | **[~]** micro-regole inline **[+]** knowledge worklist prescrittivo (path + Best Practice + Anti Pattern) **[~]** skill ALDC solo per la parte **procedurale** che BCQuality non copre |
| Flusso TDD | invariato (RED → GREEN → REFACTOR) | invariato |
| Deviazioni | non tracciate | **[+]** **dichiarazione obbligatoria**: se una knowledge prescritta non è stata applicata, path + motivo |
| Output | `📐 instr ✓ · 🧠 skill-events·EventSub+TryFunc` | **[~]** `📐 instr ✓ · 📚 bcq 5/6 applied · 🧠 skill-events·EventSub+TryFunc` **[+]** sezione `### Knowledge Deviations` — `<path> — <motivo>` (o `none`) |

*Razionale*: la dichiarazione di deviazione è **la mitigazione anti-bias più importante di
tutto il piano**. Se l'implementer ha ignorato una regola deve dirlo, e diventa la prima
cosa che la review verifica. Senza, l'allineamento diventa invisibile e non falsificabile.

### 5.5 `al-review-subagent`

Il cambio più profondo. La review **cambia mestiere**: da "trova violazioni" a "verifica
l'applicazione + trova ciò che il corpus non copre".

| | Oggi | Domani |
|---|---|---|
| Step 0 | consulta BCQuality → findings citati | **[~]** si divide in tre blocchi distinti |
| **(a) Conformance** | non esiste | **[+]** verifica le knowledge **prescritte** in implementazione + le deviazioni dichiarate. Deterministico, economico. Una deviazione non dichiarata è un finding `major` |
| **(b) Residual coverage** | è tutto Step 0 | **[~]** solo le leaf **non prescritte** in implementazione. Qui stanno i findings citati veri |
| **(c) Agent findings** | pass cross-cutting, in coda | **[~]** **obbligatorio e in testa al report.** È la valvola anti-correlazione (R1a) |
| Native residual | A/C/F/G, espande ad A–G se BCQuality assente | invariato |
| `skills-compliance` | usato nel calcolo del verdetto | **[~]** **degradato a telemetria** (R2) |
| Output JSON | `review.bcquality: {submodule-sha, outcome, skills-run}` | **[+]** `prescribed[]`, `cited[]`, `deviations[]`, `independence-ratio` (agent findings / findings totali) |
| Verdetto | dai counts | **[~]** invariato nella formula, **[+]** ma una deviazione non dichiarata pesa come `major` |

### 5.6 `dredd`

| | Oggi | Domani |
|---|---|---|
| Scope default | oggetti modificati vs `main` | **[~]** **modulo / codebase**, con preferenza per codice **non** prodotto nella sessione corrente |
| Ruolo | audit indipendente sul diff | **[~]** (1) audit su legacy e codice umano, (2) **baseline di calibrazione non allineata** |
| Output | `audit: {target, verdict, gate, bcquality, notes}` | **[+]** `audit.baseline: "aligned" \| "unaligned"` |

*Razionale*: se implementer e reviewer condividono il corpus, un terzo passaggio sullo
stesso diff con lo stesso corpus non aggiunge informazione — aggiunge costo. Il valore di
Dredd si sposta su ciò che il loop non ha toccato. Il campo `baseline` serve a impedire il
confronto fra numeri incomparabili (R10, §7.3).

### 5.7 `al-triage`

| | Oggi | Domani |
|---|---|---|
| Flusso | sintomo → riproduzione → localizzazione → causa → fix minima | invariato — è diagnosi **dinamica**, ortogonale al corpus |
| Output | diagnosi + fix proposta | **[+]** `diagnosis.bcquality-root-cause: <path> \| null` |

*Razionale*: quando la causa di un bug è una knowledge violata, citarla chiude il ciclo —
e se la causa **non** è coperta da nessuna knowledge, quello è il segnale che serve un
nuovo file in `/custom/`. Il triage diventa la sorgente naturale del backlog di knowledge.

### 5.8 `al-developer`

Fuori dal loop TDD. **[+]** Riceve lo stesso worklist prescrittivo su richiesta esplicita
(`goal: "implement AL"`), nient'altro cambia.

---

## 6. Il layer `/custom/` — preparato, non valorizzato

Cartella creata in `claude-plugin/bcquality-custom/` con `knowledge/`, `skills/`,
`templates/` e il contratto di formato. **Nessun contenuto**: la valorizzazione è
un'attività a sé.

Scelta di collocazione — nel plugin invece che in un fork di `microsoft/BCQuality`:

| | Fork `dsc-group-srl/BCQuality` | `claude-plugin/bcquality-custom/` |
|---|---|---|
| Repo da mantenere | 2 | 1 |
| Rebase su release upstream | ~mensile | mai (non tocchiamo `/microsoft/`) |
| Distribuzione | clone + pin separati | passa dal sync plugin esistente |
| Override di una regola Microsoft | sì | sì (stessa layer precedence) |

Il fork conviene solo se dovessimo **modificare** `/microsoft/` invece che sovrascriverlo.
Non è il caso.

L'overlay tecnico (copiare `knowledge/` e `skills/` in `$BCQUALITY_HOME/custom/` dopo il
fetch dell'hook) è documentato nella *Activation checklist* del README ma **non è
cablato**: a cartella vuota sarebbe un no-op, e non vale il rischio di toccare un hook che
si sincronizza in produzione ogni notte.

---

## 7. Piano operativo

### 7.1 Fasi

| Fase | Contenuto | Costo | Dipendenze | Rischi coperti |
|---|---|---|---|---|
| **0 — Igiene** | Risolvere i 5 conflitti §2.7. **Abolire il pilot** e allineare il native residual alle 17 leaf reali. **Spostare url/ref/pinnedCommit nei default dell'hook** e mettere un pin. Pulire i 4 orfani in `bc-dev` | ~1 g | nessuna | R5, R8, conflitti 1-5 |
| **1 — Reconcile del sync** | Step di delete-reconcile nel workflow del marketplace, con allowlist per i file propri di bc-dev | ~0,5 g | nessuna | **R6 — prerequisito di ogni pulizia** |
| **2 — Pulizia fork** | Decisione A2 (sync a percorso filtrato) + rimozione catena A | ~1 g | Fase 1 | R7, R11, A-B1..B5 |
| **3 — Prescrittivo minimo** | Conductor costruisce il secondo task-context; implementer riceve il worklist e dichiara le deviazioni; review aggiunge il blocco Conformance | ~2 g | Fase 0 | B1, B3, B4 |
| **4 — Ribilanciamento review** | Agent findings in testa, `skills-compliance` a telemetria, Dredd cambia scope, campi nuovi nel JSON | ~1,5 g | Fase 3 | **R1, R2, R3, R10** |
| **5 — Architect + planning** | Consultazione in design e worklist in planning | ~1,5 g | Fase 3 | B2 |
| **6 — `/custom/` valorizzato** | 10-15 knowledge file + skill di authoring + overlay cablato | **attività a sé** | Fase 4 | B6, R9 |

Fasi 0-2 sono indipendenti dalla decisione B e vanno fatte comunque: stanno producendo
codice sbagliato adesso.

### 7.2 Ordine consigliato

`1 → 0 → 2 → 3 → 4 → misura → decidi su 5 e 6`

La Fase 1 va prima di tutto: senza reconcile, ogni file che togliamo resta per sempre nel
marketplace.

### 7.3 Metriche

Da rilevare dalla Fase 3 in poi, per fase implementativa:

| Metrica | Formula | Lettura |
|---|---|---|
| **independence-ratio** | agent findings / findings totali | **La metrica chiave.** Se tende a 0, la valvola anti-correlazione è collassata (R1) e stiamo misurando solo consistenza |
| **deviation rate** | knowledge deviate / prescritte | Alta e stabile = la regola è sbagliata o non applicabile, candidata a override in `/custom/` |
| **undeclared deviations** | deviazioni trovate in review ma non dichiarate | Deve tendere a 0. Se non lo fa, l'implementer non sta leggendo il worklist |
| **prescribed ∩ cited** | knowledge prescritte che la review cita comunque | Alto = il prescrittivo non funziona; basso = funziona |
| findings totali per fase | — | **Da non leggere da solo.** Il calo è atteso e non prova nulla senza una baseline non allineata (Dredd `baseline: unaligned` su legacy) |

---

## 8. Cosa NON facciamo

- **Non passiamo al plugin ufficiale BCQuality.** Il nostro hook (cache user-scope condivisa
  in `~/.claude/bcquality`, refresh in background, zero setup per progetto) ci dà pinning e
  evidence validation che il plugin non ha; e `BCQUALITY_ENABLED_LAYERS` è dichiaratamente
  *"a selection filter, never a security boundary"*. Al massimo allineiamo le convenzioni
  di env var.
- **Non forkiamo `microsoft/BCQuality`.** §6.
- **Non tocchiamo l'hook in produzione** finché `/custom/` è vuoto. §6.
- **Non aboliamo Dredd.** Cambia scope, non sparisce: è la nostra unica baseline non
  allineata.
