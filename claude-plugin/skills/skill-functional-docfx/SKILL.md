---
name: functional-doc-docfx
description: >
  Full workflow for creating functional end-user documentation for DSC Group Business Central
  AppSource extensions, published as a bilingual (it-IT + en-US) static site using docfx.
  Use this skill whenever the user mentions: writing functional docs, user documentation,
  documenting an app for end users, docfx functional site, writing a feature page, setup
  documentation, workflow documentation, or building the functional reference for a BC extension.
  Also trigger when the user asks how to structure the toc.yml, what pages to write, how to
  document a setup table for non-technical users, or how to build and preview the functional site.
---

# Functional Documentation — docfx (Bilingual)

> Brand CSS template: `references/main.css`
> docfx.json reference template: `references/docfx-template.json`

---

## Overview

Functional docs are written entirely in Markdown — no aldoc, no XML comments. All content is
authored manually by reading the AL source and mapping every user-facing workflow into plain
language for non-technical BC users.

Every app gets **two parallel sites**, built independently:

```
guides/functional/
├── it-IT/          ← Italian site (primary)
│   ├── docfx.json
│   ├── toc.yml
│   ├── index.md
│   ├── images/     ← placeholder folder (humans add screenshots later)
│   ├── public/     ← main.css, icon
│   └── *.md        ← one .md per workflow + standard pages
└── en-US/          ← English site (same structure)
    ├── docfx.json
    ├── toc.yml
    ├── index.md
    ├── images/
    ├── public/
    └── *.md
```

Both language variants are written in the **same session**. Write all Italian content first,
then produce the full English equivalent. Content must match exactly — same pages, same sections,
same level of detail.

The functional site shares the developer site's CSS template folder:
```
template path in docfx.json → "../../developer/en-US/template/ContentTemplate"
```
No separate template folder is needed. (The extra `../` and the `en-US` segment matter: from
`guides/functional/it-IT/docfx.json` it's two levels up to `guides/`, then down through
`developer/en-US/template/ContentTemplate` — the developer site's own English-only locale
folder, created by `skill-aldoc` or `skill-developer-docfx`.)

---

## Phase 1 — Source analysis

Before writing a single word of documentation, read the AL source.

### What to read

1. **Page objects** (`page`, `pageextension`) — these define the UI the user actually sees.
   Map every action, field group, and FastTab that is visible (i.e. not hidden by `Visible = false`).
2. **Setup table(s)** — identify every field that appears on a setup page. Document those fields only.
   Do not document internal/technical fields that are never exposed in the UI.
3. **Codeunits with public procedures** — identify user-triggered operations (posting, sending,
   generating, transferring). Each one likely maps to a workflow page.
4. **Enums** — understand the values a user can select in dropdowns and what each means in
   business terms.
5. **Reports** — each report is typically a standalone workflow page.
6. **app.json** — read for: `name`, `publisher`, `version`, `description`, object ID range.

### What to extract

For each page object, extract:
- Page type (Card, List, Document, etc.) and what BC table it covers
- All user-visible fields and their captions
- All actions and what they trigger
- Any conditional visibility or editability rules that matter to the user

For each workflow (and for the setup), also extract what its tutorial needs (Phase 3):
- How the user reaches the starting page — the page caption to type in **Cerca (Alt+Q)**, or the
  page and action that opens it
- The fields the user must fill in, in the order the page presents them, and which are mandatory
  (`ShowMandatory`, `TestField`, validation code)
- The action that completes the operation and what it produces (a posted document, a ledger entry,
  a status change, a file)
- The user-facing texts it can show: `Message`, `Confirm` and `Error` labels along the path

If anything is ambiguous from the AL alone (business meaning of a field, when an action should
be used), ask the user before proceeding. Do not invent business context.

### Output of this phase

A mental (or written) inventory:

```
[ ] Setup page(s) + their fields
[ ] Core workflows (one per user-triggered operation)
[ ] Supporting list/card pages the user navigates to
[ ] Reports
[ ] Any integration points visible to the user (e.g. FactBoxes, related pages)
```

This inventory becomes the site map in Phase 2.

---

## Phase 2 — Site map and toc.yml

### Standard section layout

Every functional site follows this structure. Add or remove sections only if the app genuinely
requires it — do not add sections just to fill space.

```
1. Introduzione / Introduction
   └── index.md  (landing page — also serves as intro)

2. Configurazione / Setup
   └── setup.md  (one page covering all setup tables and their fields)

3. Funzionalità / Features
   └── [one .md per user-facing workflow]
   └── [one .md per report, if any]

4. FAQ
   └── faq.md

5. Changelog
   └── changelog.md  (placeholder — humans fill in)
```

### toc.yml template (Italian)

```yaml
- name: Introduzione
  href: index.md
- name: Configurazione
  href: setup.md
- name: Funzionalità
  items:
    - name: [Nome workflow 1]
      href: [workflow-1].md
    - name: [Nome workflow 2]
      href: [workflow-2].md
- name: FAQ
  href: faq.md
- name: Changelog
  href: changelog.md
```

### toc.yml template (English)

```yaml
- name: Introduction
  href: index.md
- name: Setup
  href: setup.md
- name: Features
  items:
    - name: [Workflow name 1]
      href: [workflow-1].md
    - name: [Workflow name 2]
      href: [workflow-2].md
- name: FAQ
  href: faq.md
- name: Changelog
  href: changelog.md
```

Workflow page filenames use lowercase kebab-case, language-neutral (same filename in both sites):
`post-document.md`, `generate-report.md`, `transfer-stock.md`, etc.

---

## Phase 3 — Write all Markdown content

Write the full Italian site first, then the full English site. Do not interleave languages.

### Writing standard

Audience: BC end users who are **not developers**. They know the BC UI but may not know this
specific extension.

Rules:
- Plain language. No AL terms, no object names, no technical identifiers.
- Field names as they appear in the BC UI (Caption), wrapped in **bold**.
- Action names as they appear in the BC UI, wrapped in **bold**.
- No field numbers, no table IDs, no codeunit names.
- Step-by-step procedures use numbered lists.
- Every workflow page and `setup.md` teach by example: each one carries a **tutorial** section
  (see the templates below) that walks one concrete, realistic case from the starting page to a
  verified result. A tutorial is not a generic list of steps — it names the page to open, the
  values to type, the action to choose, what the user sees at the end and where to check it.
- Notes and warnings use blockquotes: `> **Nota:** ...` / `> **Note:** ...`
- Each page must be self-contained — a user landing on it directly must understand the context.

### Page templates

#### index.md (landing page)

```markdown
# [App Name] — Documentazione Funzionale

[App Name] è un'estensione per Microsoft Dynamics 365 Business Central sviluppata da DSC Group Srl
che [breve descrizione funzionale in linguaggio utente — cosa fa, quale problema risolve].

---

## Funzionalità principali

- [Funzionalità 1]
- [Funzionalità 2]
- ...

---

## Informazioni

| Proprietà | Valore |
|---|---|
| Publisher | DSC Group Srl |
| Versione | [da app.json] |
| Compatibilità BC | [da app.json application version] |
```

#### setup.md

```markdown
# Configurazione

Prima di utilizzare [App Name], è necessario completare la configurazione iniziale.

## [Nome della pagina di setup in BC]

Aprire [percorso BC per raggiungere la pagina, es. "Cerca → Impostazioni Dyna ARX"].

| Campo | Descrizione |
|---|---|
| **[Caption campo 1]** | [Cosa imposta questo campo. Valori possibili se enum.] |
| **[Caption campo 2]** | [Idem.] |

> **Nota:** [Eventuali avvertenze su campi obbligatori o dipendenze tra campi.]

## Tutorial: come configurare [App Name] per la prima volta

**Scenario:** [Situazione concreta, es. "L'azienda inizia a usare [App Name] e deve impostare
i parametri minimi per [primo workflow]".]

1. Apri **Cerca (Alt+Q)**, digita `[caption della pagina di setup]` e scegli il risultato.
2. Nel campo **[Caption]**, inserisci `[valore d'esempio]`. [Perché, se non ovvio.]
3. [...]

**Risultato atteso:** [Cosa è ora possibile fare, es. "il documento può essere inviato".]

**Come verificare:** [Dove controllare che la configurazione funzioni, es. "apri un ordine e
verifica che l'azione **[Azione]** sia disponibile".]
```

Document every user-visible field from the setup page object. For enum fields, list the
available values and what each one does in plain language.

The setup tutorial covers only the **minimum** configuration needed to run the first workflow,
in the order the user must do it — including any page outside setup that must be filled first
(e.g. number series). With more than one setup page, one tutorial walks them in sequence.

#### Workflow page ([workflow-name].md)

```markdown
# [Nome del workflow — come appare all'utente]

[Paragrafo introduttivo: cosa fa questo workflow, quando si usa, quale risultato produce.]

## Prerequisiti

- [Cosa deve essere configurato o presente prima di eseguire questo workflow.]

## Tutorial: come [verbo all'infinito + oggetto, es. "registrare un trasferimento parziale"]

**Scenario:** [Situazione concreta e realistica in cui l'utente si trova, in una o due frasi.]

**Dati dell'esempio:** [I valori usati nei passi, es. articolo `1896-S`, ubicazione `BLU`,
quantità `5`.]

1. Apri **Cerca (Alt+Q)**, digita `[caption della pagina]` e scegli il risultato.
2. Scegli l'azione **[Azione]**.
3. Nel campo **[Caption]**, inserisci `[valore dell'esempio]`. [Perché, se non ovvio.]
4. [...]
5. Scegli **[Azione conclusiva]**. [Se compare una richiesta di conferma, riportane il testo
   e cosa rispondere.]

**Risultato atteso:** [Cosa vede l'utente alla fine: messaggio di conferma, documento creato,
stato cambiato.]

**Come verificare:** [Dove controllare che l'operazione sia andata a buon fine — pagina,
movimento, campo da guardare.]

**Se qualcosa va storto:**

| Messaggio | Cosa fare |
|---|---|
| "[Testo del messaggio mostrato all'utente]" | [Come correggere e riprovare.] |

## Campi

| Campo | Descrizione |
|---|---|
| **[Caption]** | [Significato funzionale per l'utente.] |

## Azioni disponibili

| Azione | Descrizione |
|---|---|
| **[Nome azione]** | [Cosa fa, quando usarla.] |

> **Nota:** [Comportamenti particolari, vincoli, o avvertenze.]
```

Omit any section that is genuinely empty (e.g. no actions on a read-only list page).
Do not add empty placeholder sections. The tutorial is the exception: every workflow page has one.

Tutorial rules:
- **Title** — always `Tutorial: come …` / `Tutorial: how to …` followed by the operation as a verb,
  so the `toc.yml` and search read as a list of things the user can learn to do.
- **One case, start to finish** — pick the most common real case, not the general one. If the
  workflow has genuinely different paths (e.g. full vs. partial transfer, with vs. without
  approval), add a second `## Tutorial: come …` section rather than branching inside the steps.
- **Concrete values** — every step that fills a field gives the example value in `code`. For
  standard BC records (customers, items, locations) use the CRONUS demo company's data; for this
  app's own records invent plausible values; for option/enum fields use a real option caption.
- **Start from search** — step 1 always opens the starting page, even if it seems obvious.
- **Messages from the source** — copy `Confirm` and `Error` texts from their labels, translated
  in the en-US site; derive the "Se qualcosa va storto" rows from the `Error`/`TestField` calls on
  the tutorial's own path only (the general error list stays in `faq.md`). Drop the table when the
  path has no user-facing errors.
- **No overlap** — the tutorial replaces the old bare "Procedura" list; fields and actions it
  doesn't touch stay in the **Campi** / **Azioni disponibili** tables, not in the steps.
- **Screenshots** — where a step needs one, leave `<!-- screenshot: [cosa mostrare] -->`; humans
  add the image into `images/` later.

English site: `## Tutorial: how to …`, **Scenario:**, **Example data:**, **Expected result:**,
**How to check:**, **If something goes wrong:** (columns *Message* / *What to do*), and
**Search (Alt+Q)** in step 1.

#### faq.md

```markdown
# Domande frequenti

## [Domanda 1?]

[Risposta.]

## [Domanda 2?]

[Risposta.]
```

Derive FAQ entries from: enum fields with non-obvious values, conditional behaviour in workflows,
common error conditions visible in the AL (e.g. Error() calls with user-facing messages),
and any setup dependency that is easy to misconfigure.

#### changelog.md

```markdown
# Changelog

## [Versione corrente — da app.json]

> Questa sezione verrà aggiornata ad ogni rilascio.

| Data | Versione | Descrizione |
|---|---|---|
| — | — | — |
```

---

## Phase 4 — docfx.json

Copy the template below for each language variant. Update the four metadata values.
The template path `../../developer/en-US/template/ContentTemplate` assumes the standard repo
structure where `guides/functional/` and `guides/developer/` are siblings under `guides/` — at the
repo root, one level back from `app/`, never nested inside it — and that
the developer site lives in its own `en-US` locale folder (two levels up from
`guides/functional/{it-IT,en-US}/`, then down into `developer/en-US/`).

```json
{
    "build": {
        "content": [
            {
                "files": [
                    "*.md",
                    "toc.yml"
                ]
            }
        ],
        "resource": [
            {
                "files": [
                    "images/**",
                    "public/**",
                    "favicon.ico",
                    "logo.svg"
                ]
            }
        ],
        "dest": "_site",
        "globalMetadata": {
            "_appName": "[App Name]",
            "_appTitle": "[App Name] — Documentazione Funzionale",
            "_appFooter": "&copy; DSC Group Srl &nbsp;|&nbsp; Realizzato con <a href=\"https://dotnet.github.io/docfx\">DocFx</a>",
            "_appLogoPath": "public/[app-icon].png",
            "_appFavIconPath": "public/[app-icon].png",
            "_enableSearch": true,
            "_disableTocFilter": false,
            "_disableToc": false,
            "_noindex": false,
            "_disableNextArticle": true
        },
        "fileMetadataFiles": [],
        "template": [
            "default",
            "modern",
            "../../developer/en-US/template/ContentTemplate"
        ],
        "postProcessors": [],
        "markdownEngineName": "markdig",
        "noLangKeyword": false,
        "keepFileLink": false,
        "cleanupCacheHistory": false,
        "disableGitFeatures": true
    }
}
```

For `en-US`, change `_appTitle` to `"[App Name] — Functional Documentation"` and
`_appFooter` to `"&copy; DSC Group Srl &nbsp;|&nbsp; Made with <a href=\"https://dotnet.github.io/docfx\">DocFx</a>"`.

---

## Phase 5 — Icon and CSS

### Find the app icon

Look here first:
```
<repo>\app\Source\Media\     ← .png or .svg
```

If not found, **ask the user** before proceeding.

Copy to both language variants:
```powershell
$icon = "C:\<repo>\app\Source\Media\<app-icon>.png"
Copy-Item $icon "C:\<repo>\docs\functional\it-IT\public\<app-icon>.png"
Copy-Item $icon "C:\<repo>\docs\functional\en-US\public\<app-icon>.png"
```

### Copy main.css

The brand CSS is bundled with this skill at `references/main.css`.
Adapt the colour variables in `:root` and `[data-bs-theme="dark"]` for the app's palette.

```powershell
$css = "<skill-references>\main.css"
Copy-Item $css "C:\<repo>\docs\functional\it-IT\public\main.css"
Copy-Item $css "C:\<repo>\docs\functional\en-US\public\main.css"
```

The shared developer template folder (`guides/developer/en-US/template/ContentTemplate`) already
contains its own `main.css` for the developer site — do not overwrite it.
The functional sites each carry their own copy in their own `public\` folder.

---

## Phase 6 — Build and preview

```powershell
# Italian site
docfx build "C:\<repo>\docs\functional\it-IT\docfx.json"
docfx serve "C:\<repo>\docs\functional\it-IT\_site" -p 8081

# English site
docfx build "C:\<repo>\docs\functional\en-US\docfx.json"
docfx serve "C:\<repo>\docs\functional\en-US\_site" -p 8082
```

Use different ports if previewing both simultaneously.

---

## What gets overwritten

| Path | Overwritten by docfx build? | Safe to edit manually? |
|---|---|---|
| `it-IT\_site\**` | Yes — every build | No |
| `en-US\_site\**` | Yes — every build | No |
| `it-IT\*.md` | Never | Yes |
| `en-US\*.md` | Never | Yes |
| `*/docfx.json` | Never | Yes |
| `*/toc.yml` | Never | Yes |
| `*/public\**` | Never | Yes |

All markdown source files are hand-authored and never touched by docfx. Only `_site\` is generated.

---

## Self-review checklist before building

- [ ] Every user-visible field from every setup page is documented in `setup.md`
- [ ] Every user-facing workflow has its own `.md` file and a `toc.yml` entry
- [ ] Every workflow page has: intro paragraph, prerequisites (if any), tutorial, fields table (if relevant), actions table (if relevant)
- [ ] `setup.md` has a first-time configuration tutorial
- [ ] Every tutorial has a scenario, example values in each data-entry step, step 1 opening the page from search, an expected result and a way to check it
- [ ] Tutorial messages (confirmations, errors) match the AL labels, translated in the en-US site
- [ ] No AL object names, field numbers, or technical identifiers appear in the content
- [ ] Field and action names match exactly what appears in the BC UI (Caption values)
- [ ] FAQ entries cover enum fields, conditional behaviour, and common error conditions
- [ ] `changelog.md` placeholder is present in both language variants
- [ ] Both `it-IT` and `en-US` sites have the same set of `.md` files and matching `toc.yml` structure
- [ ] Content in both languages is equivalent — no section present in one but missing in the other
- [ ] Icon found and copied to `public\` in both language folders
- [ ] `main.css` copied and colour variables adapted for this app's palette
- [ ] `docfx.json` metadata updated (app name, title, footer, logo path) for both variants
- [ ] `images\` folder exists in both sites (placeholder for human-added screenshots)

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `docfx serve` shows file browser | `_site` path not specified | `docfx serve "...\it-IT\_site" -p 8081` |
| Logo not showing | Icon not in `public\` or wrong filename in `docfx.json` | Verify `_appLogoPath` matches the actual filename |
| CSS not applied | `main.css` missing from `public\` or template path wrong | Check `public\main.css` exists; verify `template` array in `docfx.json` points to `../../developer/en-US/template/ContentTemplate` |
| Page missing from nav | `.md` file exists but not in `toc.yml` | Add entry to `toc.yml` |
| Build error on missing file | `toc.yml` references a `.md` that does not exist yet | Create the file or remove the `toc.yml` entry |
