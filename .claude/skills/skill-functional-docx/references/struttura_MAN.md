# Struttura standard — Manuale Utente / Guida Operativa (MAN)

Usa questa struttura come punto di partenza. Il manuale è orientato all'utente finale:
presuppone che la configurazione sia già stata fatta e si concentra sull'uso quotidiano.

---

## Sezioni standard

### 1. Introduzione

Breve paragrafo che spiega:
- A cosa serve il manuale
- A chi è destinato (ruolo utente)
- Quale modulo / funzionalità BC copre

### 2. Prerequisiti e accesso

- Permessi necessari (descritti in termini di ruolo BC, non di permission set tecnica)
- Come accedere alla funzionalità (percorso di navigazione in BC)
- Eventuali configurazioni iniziali che l'amministratore deve aver completato prima

### 3. [Nome funzionalità principale]

Una sezione per ogni funzionalità o area operativa principale.
Ogni sezione ha questa struttura interna:

#### Panoramica

Cosa fa questa funzionalità in una o due righe.

#### Come si usa

Procedura passo-passo per l'operazione principale.

1. Apri [percorso BC, es. "Cerca → Ordini di Trasferimento"]
2. Clicca su **[Azione]**
3. Compila il campo **[Campo]** con [spiegazione del valore atteso]
4. ...

#### Campi della pagina

Documenta i campi più importanti o quelli non autoesplicativi.

| Campo | Descrizione |
|---|---|
| **[Caption]** | [Spiegazione in linguaggio utente] |

#### Azioni disponibili

| Azione | Quando usarla |
|---|---|
| **[Nome]** | [Spiegazione] |

> **Nota:** [Avvertenze, comportamenti particolari.]

### 4. Casi d'uso frequenti

Scenari concreti che il cliente usa nella pratica quotidiana.
Formato: titolo dello scenario + procedura numerata.

#### Scenario: [es. "Creare un ordine di trasferimento parziale"]

1. ...
2. ...

#### Scenario: [es. "Correggere un lotto errato prima della registrazione"]

1. ...

### 5. Messaggi di errore comuni

Tabella dei messaggi d'errore che l'utente può incontrare, con causa e soluzione.

| Messaggio | Causa | Soluzione |
|---|---|---|
| "[Testo messaggio BC]" | [Perché appare] | [Come risolverlo] |

Deriva questi messaggi da: chiamate `Error()` / `Message()` nel codice AL,
o da feedback del cliente durante i test.

### 6. Domande frequenti (FAQ)

Domande reali o prevedibili dell'utente finale.

#### [Domanda 1?]

[Risposta concisa.]

#### [Domanda 2?]

[Risposta.]

### 7. Glossario (opzionale)

Termini tecnici BC o di dominio che l'utente potrebbe non conoscere.

| Termine | Definizione |
|---|---|
| [Termine] | [Spiegazione in linguaggio semplice] |

---

## Note redazionali specifiche per i manuali

- Usa **"tu"** o **"l'utente"** in modo coerente per tutto il documento (non mescolare).
- Ogni procedura deve essere eseguibile autonomamente: includi sempre il punto di partenza
  (percorso di navigazione) anche se sembra ovvio.
- Non documentare funzionalità BC standard non modificate — solo quelle personalizzate o
  quelle strettamente necessarie per contestualizzare il workflow.
- Se esistono varianti del workflow per ruoli diversi (es. magazziniere vs. responsabile),
  crea sottosezioni separate piuttosto che condizionali inline nel testo.
