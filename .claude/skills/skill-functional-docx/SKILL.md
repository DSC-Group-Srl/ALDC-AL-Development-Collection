---
name: skill-functional-docx
description: >
  Genera documenti funzionali italiani in formato .docx con il template ufficiale DSC Group Srl,
  per estensioni Business Central e workflow di software gestionale.
  Usa questa skill quando l'utente vuole creare un documento di analisi funzionale, un manuale
  utente, una guida operativa, o specifiche di personalizzazione BC da consegnare a un cliente.
  Attiva anche quando l'utente menziona: "documento di analisi", "analisi funzionale", "manuale
  utente", "doc cliente", "specifiche per il cliente", "documento BC", "scrivi il doc", oppure
  fornisce materiale grezzo (email, appunti, AL source, ticket) chiedendo di ricavarne documentazione.
  Non usare per documentazione tecnica sviluppatore (usa aldoc-docfx) né per siti docfx
  (usa functional-doc-docfx).
---

# Italian Functional Document — DSC Group Template (.docx)

**Template bundled:** `assets/template_DSC.docx`
**Docx skill:** `/mnt/skills/public/docx/SKILL.md` — leggilo prima di generare il file.

---

## Tipi di documento supportati

| Tipo | Sigla | Struttura sezioni |
|---|---|---|
| Documento di Analisi Funzionale | DAF | Vedi `references/struttura_DAF.md` |
| Manuale Utente / Guida Operativa | MAN | Vedi `references/struttura_MAN.md` |

Se il tipo non è chiaro dal contesto, chiedi all'utente prima di procedere.

---

## Fase 0 — Raccolta parametri obbligatori

Prima di scrivere qualsiasi contenuto, raccogli questi dati (deducili dal contesto se possibile,
altrimenti chiedi in un unico messaggio):

| Campo | Dove finisce nel documento | Note |
|---|---|---|
| **Nome Cliente** | Header (titolo documento) + copertina | es. "Vasconi Srl", "CEC Milano" |
| **Titolo Documento** | Header e H1 body | es. "Analisi gestione lotti – Modulo produzione" |
| **Autore** | Campo AUTORE: nella copertina | Nome consulente DSC |
| **Supervisore Progetto** | Campo SUPERVISORE PROGETTO: | BU Manager o PM |
| **Versione** | Campo VERSIONE: | default "1.0" |
| **Data** | Campo DATA: | default data odierna |
| **Note e Commenti** | Campo NOTE E COMMENTI: | opzionale, può essere vuoto |
| **Tipo documento** | Determina la struttura | DAF o MAN |

---

## Fase 1 — Analisi input

Se l'utente ha fornito materiale grezzo (email, appunti, AL source, spec ticket, screenshot),
analizzalo prima di proporre la struttura:

1. Identifica i **workflow utente** presenti nell'input (operazioni, passi, condizioni).
2. Identifica le **entità BC** coinvolte (tabelle, pagine, report, codeunit — tradotte in termini
   funzionali, mai nomi tecnici).
3. Identifica **AS-IS** (comportamento attuale, se descritto) e **TO-BE** (comportamento richiesto).
4. Segnala eventuali ambiguità che richiedono chiarimento prima di scrivere.

Proponi all'utente un **indice bozza** (titoli di sezione) da confermare o modificare prima di
procedere con la stesura completa.

---

## Fase 2 — Stesura contenuto

### Regole di scrittura

- Lingua: **italiano corretto**, tono professionale ma diretto.
- Pubblico: utenti BC non sviluppatori + project manager cliente.
- Nomi campi BC: in **grassetto**, esattamente come appaiono nell'interfaccia.
- Nomi azioni/pulsanti: in **grassetto**.
- Nomi tecnici (tabelle, codeunit, object ID): **mai** nel testo visibile al cliente.
- Note importanti: `> **Nota:** ...`
- Avvertenze: `> **Attenzione:** ...`
- Ogni sezione deve essere autocontenuta (non presupporre che il lettore abbia letto le altre).

### Elenchi e struttura del testo

**Regola principale: segui il materiale di input, non imporre una struttura.**

Se l'input dell'utente (appunti, email, spec, documento esistente) usa prosa → scrivi prosa.
Se usa elenchi puntati → usa elenchi puntati.
Se usa elenchi numerati → usa elenchi numerati.
Se mescola → valuta sezione per sezione quale forma serve davvero.

Usa elenchi numerati **solo quando l'ordine dei passi è vincolante** (procedure step-by-step
dove sbagliare la sequenza produce un errore). Non numerare liste di requisiti, caratteristiche,
o considerazioni: l'ordine non è vincolante e la numerazione crea una falsa impressione di
sequenzialità.

Usa elenchi puntati per insiemi di elementi omogenei senza ordine obbligato (es. lista di
requisiti, lista di campi fuori dalla tabella, caratteristiche di un modulo).

Usa **prosa continua** per: contesto, premessa, spiegazioni causali, ragionamenti. La prosa
fluisce meglio per il lettore non tecnico e non spezza il filo logico.

Usa **tabelle** per campi BC con descrizione, confronti, stime attività — qualsiasi cosa con
struttura righe/colonne ripetuta.

Non trasformare automaticamente in elenco numerato tutto ciò che è "una sequenza di cose":
valuta se il lettore deve eseguire i passi in ordine o solo capirli.

### Struttura heading

- `# Titolo documento` — H1, solo sulla prima riga del body
- `## Nome sezione` — H2 per le macro-sezioni
- `### Nome sottosezione` — H3 per workflow/procedure singole

Per le strutture di sezione specifiche per tipo di documento, leggi il file references corrispondente.

---

## Fase 3 — Generazione .docx

**Leggi `/mnt/skills/public/docx/SKILL.md` prima di scrivere qualsiasi codice.**

Il template di riferimento (stile Orthoservice) è in `assets/template_DSC.docx`.
Il generatore di riferimento completo (docx-js) è in `assets/gen_template_reference.js` —
leggilo per capire la struttura esatta prima di generare un documento reale.

### Palette colori DSC

```
BLUE_H1        = '365F91'   // H1 testo + bordo bottom
BLUE_H2        = '4F81BD'   // H2 bordo bottom, header tabelle
BLUE_H3        = '95B3D7'   // H3 bordo bottom
TABLE_DARK_ROW = 'A7BFDE'   // righe alternate scure (Supervisore, Data)
TABLE_LITE_ROW = 'D3DFEE'   // righe alternate chiare (Autore, Versione, Note)
```

### Font e dimensioni

```
Font globale:  Verdana
Body:          size 22 (11pt), line spacing 360 (auto), indent left 357 DXA
H1:            size 22, bold, color BLUE_H1, border bottom sz 12
H2:            size 22, color BLUE_H1, border bottom sz 8 color BLUE_H2
H3:            size 24, color BLUE_H2, border bottom sz 4 color BLUE_H3
H spacing:     H1 before 600 after 80 / H2+H3 before 200 after 80
```

### Pagina

```
Formato:    A4 (width 11906, height 16838 DXA)
Margini:    top 567, right 992, bottom 1418, left 1418, header 340
Content W:  9496 DXA
```

### Header (tutte le pagine)

Riga 1: logo DSC (cx 1195214, cy 409575 EMU) allineato a sinistra.
Riga 2: centrato — `[NOME CLIENTE] – [TITOLO]` bold size 18, poi spazi,
poi `pag. X/Y` in corsivo size 18 (PAGE + NUMPAGES field).
Logo: `assets/dsc_logo.png`

### Copertina (body, prima sezione)

Titolo grande centrato (size 52 bold): nome cliente su riga 1, titolo su riga 2.
Poi tabella metadati 2 colonne (col1=2957, col2=6436 DXA), righe alternate
TABLE_LITE_ROW / TABLE_DARK_ROW, bordi bianchi, label in grassetto, valori normali.
Righe: Autore / Supervisore progetto / Versione / Data / Note e commenti.
Poi `Sommario` H1 + campo TOC (`TOC \o "1-9" \z \u \h`).
Poi page break.

### Footer (tutte le pagine)

Bordo top sulla prima riga, centrato:
- `DSC Group Srl` bold
- indirizzi in Verdana size 14
- link http://www.dsc-group.net/ + email amministrazione@dsc-group.net

### Tabelle campi (stile documento)

Header row: shd BLUE_H2, testo bianco bold.
Righe dati: alternare TABLE_LITE_ROW / bianco, bordi FFFFFF interni.

### Naming del file output

```
[NomeCliente]_[TipoDoc]_[Titolo-kebab]_v[Versione].docx
```
Esempio: `VasconiSrl_DAF_Gestione-Lotti-Produzione_v1.0.docx`

### Note sul consulente nell'header

Il nome del consulente **non** appare più nell'header (rimosso rispetto al vecchio template).
Appare solo nel campo **Autore** della tabella di copertina.

---

## Fase 4 — Checklist pre-consegna

- [ ] Tutti i campi copertina compilati (AUTORE, SUPERVISORE, VERSIONE, DATA)
- [ ] Nome cliente corretto nel titolo header
- [ ] Nessun termine tecnico BC esposto al cliente (no object ID, no codeunit name)
- [ ] Struttura del testo coerente con l'input (prosa dove c'è prosa, elenchi dove servono)
- [ ] Campi BC in **grassetto** con caption UI esatta
- [ ] File validato con `scripts/office/validate.py`
- [ ] Nome file rispetta la convenzione di naming

---

## Note operative

- Se l'utente chiede una **revisione** di un documento esistente: unpacka il .docx caricato,
  modifica i paragrafi pertinenti, ripacca. Non rigenerare da zero.
- Se mancano informazioni essenziali (workflow incompleti, ambiguità funzionale): segnalale
  come `[DA CHIARIRE: ...]` nel documento e avvisa l'utente.
- Per documenti molto lunghi (>20 sezioni): genera prima l'indice e fatti confermare prima
  di scrivere tutto.
