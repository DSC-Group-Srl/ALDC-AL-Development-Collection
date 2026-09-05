# Struttura standard — Documento di Analisi Funzionale (DAF)

Usa questa struttura come punto di partenza. Aggiungi o rimuovi sezioni in base al progetto
reale — non aggiungere sezioni vuote o placeholder inutili.

---

## Sezioni standard

### 1. Obiettivo del documento

Breve paragrafo (3-5 righe) che descrive:
- Scopo del documento
- Ambito della personalizzazione / modulo BC coinvolto
- A chi è destinato

### 2. Contesto e situazione attuale (AS-IS)

Descrivi il processo attuale del cliente **prima** della personalizzazione.
- Come vengono gestite oggi le operazioni oggetto dell'analisi?
- Quali strumenti o workaround vengono usati?
- Quali sono le criticità o limitazioni attuali?

Ometti questa sezione se il cliente non ha un processo pre-esistente (es. nuova implementazione).

### 3. Requisiti funzionali (TO-BE)

Elenco numerato dei requisiti che la soluzione deve soddisfare.

```
1. [Requisito 1 — formulato come comportamento atteso del sistema]
2. [Requisito 2]
...
```

Per ogni requisito complesso, aggiungi una sottosezione con la descrizione dettagliata.

### 4. Workflow e procedure

Una sottosezione per ogni flusso operativo principale.

#### 4.1 [Nome workflow]

**Descrizione:** cosa fa questo workflow, quando viene usato.

**Attori:** chi esegue l'operazione (es. magazziniere, responsabile acquisti).

**Prerequisiti:** cosa deve essere presente/configurato prima.

**Procedura:**
1. Passo 1
2. Passo 2
3. ...

**Campi rilevanti:**

| Campo | Descrizione |
|---|---|
| **[Caption campo]** | [Significato funzionale, valori possibili se enum] |

**Azioni disponibili:**

| Azione | Descrizione |
|---|---|
| **[Nome azione]** | [Cosa fa, quando usarla] |

> **Nota:** [Comportamenti particolari, vincoli, casi limite.]

### 5. Configurazione / Setup

Descrive le impostazioni iniziali da completare prima di usare la funzionalità.

Struttura tabella per ogni pagina di setup:

| Campo | Descrizione |
|---|---|
| **[Caption]** | [Spiegazione + valori possibili] |

> **Attenzione:** [Dipendenze tra campi, errori comuni di configurazione.]

### 6. Integrazioni e impatti

- Quali altri moduli BC sono interessati dalla personalizzazione?
- Ci sono report, job queue, o processi schedulati coinvolti?
- Impatti su dati esistenti (migrazione, inizializzazione)?

Ometti se non pertinente.

### 7. Esclusioni e out of scope

Elenco esplicito di cosa **non** è incluso in questa analisi/sviluppo.
Utile per evitare aspettative errate da parte del cliente.

```
- [Cosa non è incluso 1]
- [Cosa non è incluso 2]
```

### 8. Appendice (opzionale)

Materiale di supporto: glossario, tabelle di riferimento, esempi di dati, link a ticket/issue.

---

## Sezioni opzionali aggiuntive

Aggiungi queste sezioni solo se il progetto lo richiede:

- **Gestione errori:** comportamento del sistema in caso di errori utente o dati mancanti
- **Permessi e ruoli:** chi può fare cosa (link alle permission set richieste)
- **Storico versioni documento:** tabella changelog del documento stesso (utile per documenti
  che evolvono nel tempo su progetti lunghi)

---

## Tabella storico versioni (se inclusa)

| Versione | Data | Autore | Descrizione modifiche |
|---|---|---|---|
| 1.0 | [data] | [autore] | Prima emissione |
