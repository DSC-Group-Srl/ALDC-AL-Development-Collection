---
name: skill-functional-docx
description: >
  Genera documenti funzionali italiani in formato .docx sul modello ufficiale DSC Group, per
  estensioni Business Central e workflow di software gestionale: documento di analisi funzionale
  (DAF) o manuale utente / guida operativa (MAN) da consegnare al cliente. Questa skill porta le
  regole sul CONTENUTO Business Central; struttura, modello, font e impaginazione vengono dal
  plugin dsc-docs (skill-brand-dsc, skill-documento-analisi, skill-manuale). Attiva anche quando
  l'utente menziona: "documento di analisi", "analisi funzionale", "manuale utente", "doc
  cliente", "specifiche per il cliente", "documento BC", "scrivi il doc", oppure fornisce
  materiale grezzo (email, appunti, AL source, ticket) chiedendo di ricavarne documentazione.
  Non usare per documentazione tecnica sviluppatore (skill-aldoc) né per siti docfx
  (skill-functional-docfx).
---

# Documento funzionale BC per il cliente (.docx)

## Chi fa cosa

| Cosa | Dove |
|---|---|
| Contenuto Business Central (cosa leggere nell'AL, come nominare campi e pagine, cosa non esporre) | **questa skill** |
| Struttura delle sezioni DAF / MAN, dati di copertina, regole di scrittura generali | `dsc-docs:skill-documento-analisi`, `dsc-docs:skill-manuale` |
| Modello, font, logo, intestazione, piè di pagina, generazione e verifica del .docx | `dsc-docs:skill-brand-dsc` |

La formattazione DSC vive **solo** nel plugin **dsc-docs** (modelli ufficiali della cartella
MODELLI DOCUMENTI su Teams). Questa skill non la ripete e non porta modelli propri.

**Se dsc-docs non è installato** (le sue skill non compaiono): fermati prima di generare il file
e dillo all'utente — "serve il plugin dsc-docs del marketplace DSC: `/plugin install
dsc-docs@dscgroup-bc-nav-agentic-development`". Non improvvisare un modello o uno stile: è così
che nascevano i DAF in Verdana con l'intestazione di un altro progetto.

## Tipi di documento

| Tipo | Sigla | Skill dsc-docs |
|---|---|---|
| Documento di Analisi Funzionale | DAF | `dsc-docs:skill-documento-analisi` |
| Manuale Utente / Guida Operativa | MAN | `dsc-docs:skill-manuale` |

Se il tipo non è chiaro dal contesto, chiedi all'utente prima di procedere.

## Fase 0 — Dati

Carica `dsc-docs:skill-brand-dsc` e la skill del tipo: elencano i dati di copertina (cliente,
titolo, autore, supervisore, versione, data, note) e il loro formato. Raccoglili in un solo
messaggio, deducendo dal contesto quello che puoi (cliente e app da `app.json`, dal repository o
dall'Issue Business Central collegata).

## Fase 1 — Analisi dell'input Business Central

Se l'utente ha fornito materiale grezzo (email, appunti, sorgente AL, ticket, screenshot):

1. Individua i **workflow utente** (operazioni, passi, condizioni).
2. Individua le **entità BC** coinvolte — tabelle, pagine, report, codeunit — e traducile in
   termini funzionali: il cliente vede "la scheda **Articolo**", non `Table 27 Item`.
3. Dal sorgente AL ricava le **caption** a schermo (`Caption`, XLIFF it-IT) dei campi e delle
   azioni, non i nomi AL; i messaggi d'errore dalle `Label` usate in `Error()` / `Message()`.
4. Separa **AS-IS** (comportamento attuale) e **TO-BE** (comportamento richiesto).
5. Segnala le ambiguità prima di scrivere.

Proponi l'indice (struttura della skill dsc-docs del tipo) e fallo confermare.

## Fase 2 — Regole di contenuto BC

Valgono in aggiunta alle regole di scrittura della skill dsc-docs del tipo:

- Pubblico: utenti BC non sviluppatori e project manager del cliente.
- Nomi di campi, pagine e azioni BC in **grassetto**, **esattamente** come appaiono
  nell'interfaccia in italiano (caption it-IT).
- **Mai** nel testo per il cliente: ID o nomi di oggetti AL, nomi di tabelle/codeunit, nomi di
  variabili, eventi, permission set tecniche. Le autorizzazioni si descrivono come ruoli.
- Funzionalità standard BC non modificate: solo quando servono a dare contesto al workflow
  personalizzato.
- Personalizzazione vs standard: dillo chiaramente quando un comportamento è una personalizzazione
  DSC per quel cliente.

## Fase 3 — Generazione

Scrivi il contenuto nel Markdown di `dsc-docs:skill-brand-dsc` (`references/markdown-dsc.md`) e
genera con il suo `dscdoc.py` (`--tipo analisi` per il DAF, `--tipo manuale` per il MAN). Poi
segui la verifica di `skill-brand-dsc` (PDF e lettura delle pagine quando c'è Office).

### Dove salvare il file (repository)

Mai una cartella inventata sul momento. Il percorso canonico, relativo alla radice del repo, è:

| Tipo documento | Cartella |
|---|---|
| DAF — Analisi funzionale | `guides/word/DAF/` |
| MAN — Manuale utente / guida operativa | `guides/word/Manuals/` |
| Note di rilascio | `guides/word/Release Notes/` |

Nome del file: la convenzione di `dsc-docs:skill-brand-dsc` (`DAF_<Cliente>_<Argomento>_v<versione>.docx`).
Il Markdown sorgente resta accanto al .docx con lo stesso nome (`.md`): è da lì che si rigenera
la versione successiva.

Crea la cartella se non esiste. I `.docx` sotto `guides/word/` **sono versionati**: lo standard
di repository DSC ha `*.docx` nel `.gitignore`, quindi se il `.gitignore` del repo ignora i
`.docx` aggiungi in coda, una volta sola:

```gitignore
# Word deliverables for the customer (skill-functional-docx)
!guides/word/
!guides/word/**
!guides/word/**/*.docx
```

Poi verifica con `git check-ignore -v "guides/word/<cartella>/<file>.docx"`: nessun output =
il file è tracciabile. Se il repo non ha `guides/` (fuori standard), chiedi all'utente dove
salvare invece di scegliere tu.

## Fase 4 — Checklist pre-consegna

- [ ] Checklist della skill dsc-docs del tipo e verifica di `skill-brand-dsc` superate
      (`dscdoc.py` non segnala problemi, PDF guardato)
- [ ] Nessun termine tecnico BC esposto al cliente (object ID, nomi AL, codeunit)
- [ ] Campi e azioni BC in **grassetto** con la caption it-IT esatta
- [ ] File in `guides/word/{DAF,Manuals,Release Notes}/`, non ignorato da git, con il `.md` accanto

## Note operative

- **Revisione** di un documento esistente: modifica quel file (o il suo `.md` e rigenera), non
  ricominciare da zero.
- Informazioni mancanti: `[DA CHIARIRE: ...]` nel punto esatto, e avvisa l'utente.
- Documenti molto lunghi (>20 sezioni): fai confermare l'indice prima di scrivere tutto.
