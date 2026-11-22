#!/usr/bin/env python3
"""Testes de política do repositório Tabletop (rodam no CI e antes de todo push de trem).

Uso: python3 scripts/ci/politica.py --base <ref ou sha>   (ex.: --base origin/main)

Regras:
  1. Migrations só com acréscimos: nenhuma migration que já existe na base pode ser
     editada, renomeada ou apagada; as novas seguem a numeração (NNNN_nome.sql).
  2. Nada de arquivos .env (só .env.example) nem de worktrees ou config local do Claude no git.
  3. Nada que pareça chave ou segredo nos arquivos versionados.
  4. Agentes (.claude/agents/*.md) e skills (.claude/skills/*/SKILL.md) com frontmatter válido.
Só usa a biblioteca padrão do Python.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

RAIZ = Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                           text=True, check=True).stdout.strip())
MIGRATIONS = "supabase/migrations/"
NOME_MIGRATION = re.compile(r"^supabase/migrations/(\d{4})_[a-z0-9_]+\.sql$")

SEGREDOS = [
    ("JWT (chave do Supabase)", re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}")),
    ("chave secreta do Supabase", re.compile(r"\bsb_secret_[A-Za-z0-9_-]{10,}")),
    ("token do GitHub", re.compile(r"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}|\bgithub_pat_[A-Za-z0-9_]{30,}")),
    ("chave do Stripe", re.compile(r"\b(sk|rk)_(live|test)_[A-Za-z0-9]{16,}")),
    ("chave da AWS", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("chave da Anthropic", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{20,}")),
    ("chave privada", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
]

erros = []


def git(*args):
    return subprocess.run(["git", *args], cwd=RAIZ, capture_output=True, text=True, check=True).stdout


def checar_migrations(base):
    try:
        mudancas = git("diff", "--name-status", "-M", base, "HEAD", "--", MIGRATIONS)
    except subprocess.CalledProcessError as e:
        erros.append(f"não foi possível comparar com a base {base!r}: {e.stderr.strip()}")
        return
    na_base = [l for l in git("ls-tree", "-r", "--name-only", base, "--", MIGRATIONS).splitlines()]
    numeros_base = [int(m.group(1)) for f in na_base if (m := NOME_MIGRATION.match(f))]
    proximo = max(numeros_base, default=0) + 1
    novas = []
    for linha in mudancas.splitlines():
        partes = linha.split("\t")
        status, arquivo = partes[0], partes[-1]
        if status.startswith("A"):
            novas.append(arquivo)
        else:
            alvo = partes[1]
            erros.append(f"{alvo}: migration que já existe não pode ser editada, renomeada ou apagada "
                         f"(status {status}). Corrija com uma migration nova.")
    numeros = []
    for arquivo in sorted(novas):
        m = NOME_MIGRATION.match(arquivo)
        if not m:
            erros.append(f"{arquivo}: nome de migration fora do padrão NNNN_nome.sql (minúsculas e _).")
            continue
        numeros.append(int(m.group(1)))
    for esperado, n in zip(range(proximo, proximo + len(numeros)), sorted(numeros)):
        if n != esperado:
            erros.append(f"migrations novas devem continuar a numeração a partir de {proximo:04d}; "
                         f"encontrada {n:04d}. Peça o número ao maestro.")
            break


def checar_arquivos_proibidos(versionados):
    for f in versionados:
        nome = Path(f).name
        if nome.startswith(".env") and nome != ".env.example":
            erros.append(f"{f}: arquivo .env não entra no repositório. Remova e use .env.example.")
        if f.startswith(".claude/worktrees/"):
            erros.append(f"{f}: worktrees das sessões não entram no repositório.")
        if f.endswith(".claude/settings.local.json"):
            erros.append(f"{f}: configuração local do Claude não entra no repositório.")


def checar_segredos(versionados):
    for f in versionados:
        caminho = RAIZ / f
        if not caminho.is_file() or caminho.stat().st_size > 2_000_000:
            continue
        try:
            texto = caminho.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for n, linha in enumerate(texto.splitlines(), 1):
            for nome, padrao in SEGREDOS:
                if padrao.search(linha):
                    erros.append(f"{f}:{n}: parece {nome}. Segredos não entram no repositório.")


def frontmatter(caminho):
    texto = caminho.read_text(encoding="utf-8")
    if not texto.startswith("---\n"):
        return None
    fim = texto.find("\n---", 4)
    if fim == -1:
        return None
    campos = {}
    for linha in texto[4:fim].splitlines():
        if ":" in linha and not linha.startswith((" ", "\t", "-")):
            chave, valor = linha.split(":", 1)
            campos[chave.strip()] = valor.strip().strip('"')
    return campos


def checar_agentes():
    pasta = RAIZ / ".claude" / "agents"
    if not pasta.is_dir():
        return
    exigencias = {
        "revisor": {"model": "opus", "effort": "high"},
        "explorador": {"model": "haiku"},
        "plataforma-ci": {"model": "opus"},
    }
    for arq in sorted(pasta.glob("*.md")):
        rel = arq.relative_to(RAIZ)
        fm = frontmatter(arq)
        if fm is None:
            erros.append(f"{rel}: sem frontmatter (--- ... ---).")
            continue
        for campo in ("name", "description", "model"):
            if not fm.get(campo):
                erros.append(f"{rel}: falta o campo '{campo}' no frontmatter.")
        nome = fm.get("name", "")
        if nome and nome != arq.stem:
            erros.append(f"{rel}: 'name' ({nome}) deve ser igual ao nome do arquivo ({arq.stem}).")
        regra = exigencias.get(nome)
        if nome.startswith("dev-"):
            regra = {"model": "sonnet", "effort": "high"}
        for campo, valor in (regra or {}).items():
            if fm.get(campo) != valor:
                erros.append(f"{rel}: '{campo}' deve ser '{valor}' (está '{fm.get(campo, '')}').")
        if nome == "revisor":
            proibidas = {t.strip() for t in fm.get("disallowedTools", "").split(",")}
            if not {"Write", "Edit"} <= proibidas:
                erros.append(f"{rel}: o revisor não pode editar (disallowedTools com Write e Edit).")


def checar_skills():
    pasta = RAIZ / ".claude" / "skills"
    if not pasta.is_dir():
        return
    for arq in sorted(pasta.glob("*/SKILL.md")):
        rel = arq.relative_to(RAIZ)
        fm = frontmatter(arq)
        if fm is None:
            erros.append(f"{rel}: sem frontmatter (--- ... ---).")
            continue
        for campo in ("name", "description"):
            if not fm.get(campo):
                erros.append(f"{rel}: falta o campo '{campo}' no frontmatter.")
        if fm.get("name") and fm["name"] != arq.parent.name:
            erros.append(f"{rel}: 'name' deve ser igual ao nome da pasta ({arq.parent.name}).")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--base", default="origin/main", help="ref ou sha da base (padrão: origin/main)")
    args = p.parse_args()

    versionados = git("ls-files").splitlines()
    checar_migrations(args.base)
    checar_arquivos_proibidos(versionados)
    checar_segredos(versionados)
    checar_agentes()
    checar_skills()

    if erros:
        print(f"Política: {len(erros)} problema(s)\n")
        for e in erros:
            print(f"  - {e}")
        return 1
    print(f"Política: ok ({len(versionados)} arquivos versionados, base {args.base}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
