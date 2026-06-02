#!/usr/bin/env python3
"""
Extracteur de relevés de compte La Banque Postale (LBP) -> JSON

Usage:
    python lbp_parser.py releve1.pdf [releve2.pdf ...]
    python lbp_parser.py *.pdf --merge -o sortie.json

Produit un fichier JSON par relevé (ou un seul fichier groupé avec --merge).
Aucune donnée n'est envoyée sur internet : tout est traité localement.

Extraction PDF (par ordre de priorité) :
  1. pdftotext -layout (poppler-utils) — le plus fiable, préserve les colonnes
  2. PyMuPDF (fitz) — fallback, reconstruit l'alignement via coordonnées
  3. pypdf en mode layout — dernier recours

IMPORTANT : la détection débit/crédit repose sur l'alignement des colonnes.
Seules les méthodes qui préservent cet alignement sont utilisées.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

try:
    import fitz  # PyMuPDF
except ImportError:
    fitz = None

try:
    from pypdf import PdfReader
except ImportError:
    PdfReader = None


# ==========================================================================
# 1. EXTRACTION TEXTE — chaque méthode renvoie une liste de pages (str) ou None
# ==========================================================================
def _extract_with_pdftotext(pdf_path):
    """Méthode primaire : poppler conserve parfaitement l'alignement.

    IMPORTANT : pdftotext émet de l'UTF-8. On lit donc la sortie en *bytes*
    puis on décode explicitement en UTF-8, sinon sur un système dont l'encodage
    local n'est pas UTF-8 (ex. Windows FR / cp1252) le texte serait corrompu
    ('Épargne' -> 'Ã‰pargne'), ce qui casserait toute la détection.
    """
    if not shutil.which("pdftotext"):
        return None
    res = subprocess.run(
        ["pdftotext", "-enc", "UTF-8", "-layout", str(pdf_path), "-"],
        capture_output=True,  # bytes, pas de décodage automatique
    )
    if not res.stdout:
        return None
    text = res.stdout.decode("utf-8", errors="replace")
    return text.split("\f")


def _extract_with_pymupdf(pdf_path):
    """
    Fallback PyMuPDF. get_text('text') NE préserve PAS l'alignement des
    colonnes de façon fiable (débit et crédit se retrouvent à la même
    position) -> on reconstruit nous-mêmes un texte à colonnes fixes à
    partir des coordonnées x des mots, qui elles sont fiables.
    """
    if fitz is None:
        return None
    doc = fitz.open(str(pdf_path))
    pages = []
    for page in doc:
        words = page.get_text("words")  # (x0,y0,x1,y1,mot,bloc,ligne,wno)
        if not words:
            pages.append("")
            continue
        scale = 0.50  # ~0.5 caractère par point -> largeur ~150 colonnes
        lines = defaultdict(list)
        for x0, y0, x1, y1, w, *_ in words:
            lines[round(y0 / 3.0)].append((x0, w))
        out = []
        for key in sorted(lines):
            row = sorted(lines[key])
            # Recoller un séparateur de milliers : '1' suivi de '964,78'
            # (PyMuPDF sépare parfois '1 964,78' en deux mots) -> '1 964,78'
            merged = []
            for x0, w in row:
                if (merged and re.fullmatch(r"\d{1,3}", merged[-1][1])
                        and re.fullmatch(r"\d{3}(?:[ ,]\d{3})*(?:,\d{2})?", w)):
                    merged[-1] = (merged[-1][0], merged[-1][1] + " " + w)
                else:
                    merged.append((x0, w))
            buf = ""
            for x0, w in merged:
                col = int(x0 * scale)
                if col <= len(buf):
                    col = len(buf) + 1
                buf += " " * (col - len(buf)) + w
            out.append(buf)
        pages.append("\n".join(out))
    return pages


def _extract_with_pypdf(pdf_path):
    if PdfReader is None:
        return None
    reader = PdfReader(str(pdf_path))
    pages = []
    for page in reader.pages:
        pages.append(page.extract_text(extraction_mode="layout") or "")
    return pages


def _fix_mojibake(pages):
    """
    Filet de sécurité : si du texte UTF-8 a été décodé par erreur en cp1252
    (motifs typiques 'Ã©', 'Â¤', 'â€™'), on tente de le réparer en ré-encodant
    en cp1252 puis en redécodant en UTF-8. Sans effet si le texte est déjà sain.
    """
    fixed = []
    for p in pages:
        if any(tok in p for tok in ("Ã©", "Ã‰", "Â¤", "Â°", "â€™", "Ã¨", "Ã ")):
            try:
                p = p.encode("cp1252", errors="ignore").decode("utf-8", errors="ignore")
            except (UnicodeDecodeError, UnicodeEncodeError):
                pass
        fixed.append(p)
    return fixed


def extract_layout(pdf_path):
    pages = _extract_with_pdftotext(pdf_path)
    if pages:
        return _fix_mojibake(pages)
    # Fallbacks moins fiables : on prévient l'utilisateur.
    print(
        "  ⚠ 'pdftotext' (poppler-utils) introuvable — utilisation d'un "
        "extracteur de secours.\n"
        "    Les opérations restent correctes, mais l'en-tête 'Situation des "
        "comptes' peut être incomplet.\n"
        "    Pour une fiabilité maximale : installez poppler-utils "
        "(apt install poppler-utils / brew install poppler).",
        file=sys.stderr,
    )
    for method in (_extract_with_pymupdf, _extract_with_pypdf):
        pages = method(pdf_path)
        if pages:
            return _fix_mojibake(pages)
    sys.exit(
        "ERREUR : impossible d'extraire le texte du PDF.\n"
        "Installez poppler-utils (commande 'pdftotext'), ou la dépendance "
        "Python 'pymupdf' ou 'pypdf'."
    )


# ==========================================================================
# 2. OUTILS MONTANTS / LIBELLÉS
# ==========================================================================
def parse_amount(s):
    """'1 964,78' -> 1964.78 ; gère espaces fines et insécables."""
    s = s.replace("\u202f", " ").replace("\xa0", " ")
    s = s.replace(" ", "").replace(",", ".")
    return round(float(s), 2)


# Un montant = 1 à 3 chiffres, groupes de milliers séparés par une espace
# (normale / fine / insécable), puis ',dd'. Pas de lookbehind fragile :
# on s'appuie sur la POSITION dans la ligne pour distinguer un vrai montant
# d'un fragment de date.
AMOUNT_RE = re.compile(r"\d{1,3}(?:[ \u202f\xa0]\d{3})*,\d{2}")
DATE_LINE_RE = re.compile(r"^\s*(\d{2}/\d{2})\s+(.*)$")
# Montant situé en colonne (précédé d'au moins 2 espaces) : vrai montant,
# par opposition à un fragment collé comme '30.12.25'. On teste ça via la
# position plutôt que via un lookbehind regex.
def rightmost_amount(line):
    """Renvoie (match) du montant le plus à droite RÉELLEMENT en colonne."""
    cands = [m for m in AMOUNT_RE.finditer(line)
             if m.start() == 0 or line[m.start() - 1] == " "]
    return cands[-1] if cands else None


NOISE_MARKERS = ["REF :", "IDENT :", "MANDAT :", "REFERENCE :", "RUM"]
IBAN_RE = re.compile(r"\bFR\d{2}[0-9A-Z ]+", re.IGNORECASE)
COMPTE_IBAN_RE = re.compile(r"\bCOMPTE\s+[A-Z]{2}\d[0-9A-Z]*")


def clean_label(parts):
    text = " ".join(p.strip() for p in parts if p.strip())
    cut = len(text)
    for mk in NOISE_MARKERS:
        i = text.find(mk)
        if i != -1:
            cut = min(cut, i)
    text = text[:cut]
    text = COMPTE_IBAN_RE.sub("", text)
    text = IBAN_RE.sub("", text)
    text = re.sub(r"DATE DE VALEUR[\d  ]*", "", text)
    # Longs codes internes alphanumériques (8+ car. mêlant chiffres et lettres)
    text = re.sub(r"\b(?=[0-9A-Z/\-]*\d)(?=[0-9A-Z/\-]*[A-Z])[0-9A-Z/\-]{8,}\b",
                  "", text)
    text = re.sub(r"\b\d{8,}\b", "", text)
    text = re.sub(r"\s{2,}", " ", text).strip(" -")
    return text


# ==========================================================================
# 3. DÉTECTION COLONNE DÉBIT / CRÉDIT
# ==========================================================================
def find_split_column(page_text):
    """
    Position de césure entre colonnes débit et crédit, déduite de l'en-tête
    'Débit (¤)  Crédit (¤)'. On prend le point situé entre la FIN de la
    colonne débit et le DÉBUT de la colonne crédit.
    """
    for line in page_text.splitlines():
        if "Débit" in line and "Crédit" in line:
            d_end = line.index("Débit") + len("Débit (¤)")
            c_start = line.index("Crédit")
            return (d_end + c_start) // 2
    return None


def amount_side(line, split_col):
    """('debit'|'credit', valeur) selon la FIN du montant vs la césure."""
    m = rightmost_amount(line)
    if not m:
        return None
    val = parse_amount(m.group())
    side = "credit" if m.end() > split_col else "debit"
    return side, val


# ==========================================================================
# 4. PARSING DES OPÉRATIONS
# ==========================================================================
def parse_operations(tagged_lines):
    """tagged_lines : liste de (ligne, split_col_de_la_page)."""
    ops = []
    current = None

    def flush():
        nonlocal current
        if current:
            current["libelle"] = clean_label(current["_frag"])
            del current["_frag"]
            ops.append(current)
            current = None

    for line, split_col in tagged_lines:
        if not line.strip():
            continue
        if ("Total des opérations" in line or "Nouveau solde" in line
                or "Ancien solde" in line):
            continue
        m = DATE_LINE_RE.match(line)
        if m:
            flush()
            date, rest = m.group(1), m.group(2)
            current = {"date": date, "libelle": "",
                       "debit": None, "credit": None, "_frag": []}
            side = amount_side(line, split_col)
            if side:
                current[side[0]] = side[1]
                am = rightmost_amount(line)
                if am:
                    stripped = line[:am.start()] + line[am.end():]
                    mm = DATE_LINE_RE.match(stripped)
                    rest = mm.group(2) if mm else ""
            current["_frag"].append(rest)
        else:
            if current is not None:
                current["_frag"].append(line)
    flush()
    return ops


# ==========================================================================
# 5. SITUATION DES COMPTES (en-tête)
# ==========================================================================
ACCOUNT_NAMES = (r"Compte Courant Postal|Livret Jeune Swing|Livret A|"
                 r"Livret d.Épargne Populaire|Livret d.Epargne Populaire")


def _norm_compte(name):
    return name.replace("Epargne", "Épargne").strip()


def parse_situation(page1):
    situation = {"date": None, "comptes": []}
    for line in page1.splitlines():
        m = re.search(r"Situation de vos comptes\s+au\s+(\d{2} \w+ \d{4})", line)
        if m:
            situation["date"] = m.group(1)
        cm = re.match(r"\s*(" + ACCOUNT_NAMES + r")\b", line)
        if cm and AMOUNT_RE.search(line):
            am = AMOUNT_RE.search(line)
            # signe : un '-' / '–' juste avant le montant => solde négatif
            neg = re.search(r"[-–]\s*" + re.escape(am.group()), line)
            situation["comptes"].append({
                "compte": _norm_compte(cm.group(1)),
                "solde": (-1 if neg else 1) * parse_amount(am.group()),
            })
    return situation


# ==========================================================================
# 6. ASSEMBLAGE DU RELEVÉ
# ==========================================================================
COMPTE_HEADER_RE = re.compile(r"^\s*(" + ACCOUNT_NAMES + r")\s+n[°º]", re.M)


def parse_statement(pages):
    # Chaque page a sa propre colonne de césure (l'indentation varie selon la
    # page). On annote donc chaque ligne avec le split de SA page, puis on
    # travaille sur le texte concaténé sans perdre cette information.
    page_splits = []
    last = 140
    for p in pages:
        c = find_split_column(p)
        if c:
            last = c
        page_splits.append(last)

    # Liste de tuples (ligne, split_col) pour tout le relevé
    tagged = []
    for p, sc in zip(pages, page_splits):
        for line in p.splitlines():
            tagged.append((line, sc))

    full = "\n".join(pages)
    result = {
        "banque": "La Banque Postale",
        "releve": {},
        "situation": parse_situation(pages[0]),
        "compte_courant": None,
        "comptes_epargne": [],
    }
    rm = re.search(r"Relevé de vos comptes\s*-\s*n[°º]\s*(\d+)", full)
    dm = re.search(r"Relevé édité le\s+(\d{2} \w+ \d{4})", full)
    if rm:
        result["releve"]["numero"] = int(rm.group(1))
    if dm:
        result["releve"]["date_edition"] = dm.group(1)

    result["compte_courant"] = _parse_ccp(tagged)
    result["comptes_epargne"] = _parse_epargne(tagged)

    cc = result["compte_courant"]
    controle = {"coherent": None, "ecart": None}
    try:
        attendu = round(cc["ancien_solde"]["montant"]
                        + (cc["total_credit"] or 0)
                        - (cc["total_debit"] or 0), 2)
        controle["ecart"] = round(attendu - cc["nouveau_solde"]["montant"], 2)
        controle["coherent"] = abs(controle["ecart"]) < 0.01
    except (TypeError, KeyError):
        pass
    result["controle_coherence"] = controle
    return result


def _solde_from_line(line):
    m = re.search(r"(?:Ancien|Nouveau) solde au\s+(\d{2}/\d{2}/\d{4})", line)
    if not m:
        return None
    am = AMOUNT_RE.search(line)
    return {"date": m.group(1),
            "montant": parse_amount(am.group()) if am else None}


def _parse_ccp(tagged):
    # Zone CCP = avant "Comptes d'Épargne"
    idx = next((i for i, (l, _) in enumerate(tagged)
                if "Comptes d'Épargne" in l), len(tagged))
    zone = tagged[:idx]

    ccp = {"type": "Compte Courant Postal", "ancien_solde": None,
           "operations": [], "total_debit": None, "total_credit": None,
           "nouveau_solde": None}

    for line, _ in zone:
        if "Ancien solde au" in line:
            ccp["ancien_solde"] = _solde_from_line(line)
            break

    start = next((i for i, (l, _) in enumerate(zone) if "Ancien solde au" in l), 0)
    end = next((i for i, (l, _) in enumerate(zone) if "Total des opérations" in l),
               len(zone))
    ccp["operations"] = parse_operations(zone[start + 1:end])

    for line, sc in zone:
        if "Total des opérations" in line:
            amts = [m for m in AMOUNT_RE.finditer(line)
                    if m.start() == 0 or line[m.start() - 1] == " "]
            if len(amts) >= 2:
                ccp["total_debit"] = parse_amount(amts[-2].group())
                ccp["total_credit"] = parse_amount(amts[-1].group())
            elif len(amts) == 1:
                side = amount_side(line, sc)
                if side:
                    ccp["total_" + side[0]] = side[1]
        if "Nouveau solde au" in line:
            ccp["nouveau_solde"] = _solde_from_line(line)
    return ccp


def _parse_epargne(tagged):
    idx = next((i for i, (l, _) in enumerate(tagged)
                if "Comptes d'Épargne" in l), None)
    if idx is None:
        return []
    zone = tagged[idx:]
    cut = next((i for i, (l, _) in enumerate(zone)
                if "Pour faire opposition" in l), len(zone))
    zone = zone[:cut]

    # Indices des en-têtes de livret
    header_idx = [i for i, (l, _) in enumerate(zone)
                  if COMPTE_HEADER_RE.match(l)]
    livrets = []
    for k, hi in enumerate(header_idx):
        seg_end = header_idx[k + 1] if k + 1 < len(header_idx) else len(zone)
        seg = zone[hi:seg_end]
        name = _norm_compte(COMPTE_HEADER_RE.match(seg[0][0]).group(1))
        livret = {"type": name, "ancien_solde": None,
                  "operations": [], "nouveau_solde": None}
        for line, _ in seg:
            if "Ancien solde au" in line:
                livret["ancien_solde"] = _solde_from_line(line)
            if "Nouveau solde au" in line:
                livret["nouveau_solde"] = _solde_from_line(line)
        s = next((j for j, (l, _) in enumerate(seg) if "Ancien solde au" in l), 0)
        e = next((j for j, (l, _) in enumerate(seg) if "Nouveau solde au" in l),
                 len(seg))
        livret["operations"] = parse_operations(seg[s + 1:e])
        livrets.append(livret)
    return livrets


# ==========================================================================
# 7. CLI
# ==========================================================================
def main():
    ap = argparse.ArgumentParser(
        description="Extraction des relevés La Banque Postale (PDF -> JSON)")
    ap.add_argument("pdfs", nargs="+", help="Fichier(s) PDF de relevé")
    ap.add_argument("-o", "--output", help="Fichier JSON de sortie")
    ap.add_argument("--merge", action="store_true",
                    help="Regrouper tous les relevés dans un seul JSON")
    ap.add_argument("--indent", type=int, default=2, help="Indentation JSON")
    args = ap.parse_args()

    results = []
    for pdf in args.pdfs:
        path = Path(pdf)
        if not path.exists():
            print(f"  ! introuvable : {pdf}", file=sys.stderr)
            continue
        data = parse_statement(extract_layout(path))
        data["_fichier_source"] = path.name
        results.append((path, data))
        ctrl = data["controle_coherence"]
        flag = ("✓ solde cohérent" if ctrl.get("coherent")
                else f"⚠ écart {ctrl.get('ecart')} €" if ctrl.get("coherent") is False
                else "? non vérifiable")
        print(f"  ✓ {path.name} : "
              f"{len(data['compte_courant']['operations'])} opérations CCP, "
              f"{len(data['comptes_epargne'])} livret(s) — {flag}")

    if args.merge:
        out = Path(args.output or "releves_lbp.json")
        out.write_text(json.dumps([d for _, d in results],
                       ensure_ascii=False, indent=args.indent), encoding="utf-8")
        print(f"\nJSON groupé écrit : {out}")
    else:
        for path, data in results:
            out = (Path(args.output) if args.output and len(results) == 1
                   else path.with_suffix(".json"))
            out.write_text(json.dumps(data, ensure_ascii=False, indent=args.indent),
                           encoding="utf-8")
            print(f"  → {out}")


if __name__ == "__main__":
    main()
