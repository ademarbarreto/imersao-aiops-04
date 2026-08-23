#!/usr/bin/env bash
# Lint estático de Dockerfile com hadolint, na política da skill containerizacao-docker.
#
# Uso: lint-dockerfile.sh [DOCKERFILE...]      (sem argumento = descobre os do projeto)
#
# Este script existe porque a skill enuncia em prosa regras que uma ferramenta
# verifica em milissegundos — tag fixa, exec form, não-root, WORKDIR absoluto.
# Conferir de olho o arquivo que você mesmo acabou de escrever é a forma menos
# confiável de checagem que existe, e o gate de runtime (Fase 8) custa um build
# inteiro para pegar só uma parte desses erros.
#
# Além do hadolint, o script aplica uma checagem própria (SKILL001) para a regra
# de usuário não-root, que o hadolint sozinho não cobre — ver checa_usuario_final.
#
# Política: error, warning e achados de política bloqueiam; info e style são observação.
#
# Saída: um bloco legível por arquivo, e uma linha-resumo final estável,
# própria para ser citada no relatório de evidências.
#
# Códigos de saída:
#   0  liberado  — nenhum error/warning/política (pode haver info/style)
#   1  bloqueado — há achado a resolver, ou um caminho passado não existe
#   2  pulado    — hadolint não está instalado; NÃO é reprovação

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v hadolint >/dev/null 2>&1; then
    echo "LINT: PULADO — hadolint não encontrado (instale com: brew install hadolint)"
    echo "   O lint não bloqueia por ausência da ferramenta. Siga para a validação"
    echo "   em runtime (Fase 8) e registre no relatório que o lint não rodou."
    exit 2
fi

# Config do projeto tem precedência: se o repositório já tem a sua, ela é a
# fonte de verdade. Sem ela, vale a da skill (que nunca é escrita no repo).
CONFIG=""
for candidato in .hadolint.yaml .hadolint.yml hadolint.yaml; do
    if [[ -f "$candidato" ]]; then
        CONFIG="$(cd "$(dirname "$candidato")" && pwd)/$(basename "$candidato")"
        break
    fi
done
[[ -z "$CONFIG" ]] && CONFIG="$SKILL_DIR/assets/hadolint.yaml"

# Alvos: os passados na linha de comando, ou o que houver no projeto.
ARQUIVOS=()
if [[ $# -gt 0 ]]; then
    ARQUIVOS=("$@")
else
    while IFS= read -r encontrado; do
        ARQUIVOS+=("$encontrado")
    done < <(find . -type f \( -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.Dockerfile' \) \
        -not -path './.git/*' \
        -not -path '*/node_modules/*' \
        -not -path '*/vendor/*' \
        -not -path '*/.venv/*' \
        -not -path '*/target/*' | sort)
fi

if [[ ${#ARQUIVOS[@]} -eq 0 ]]; then
    echo "LINT: PULADO — nenhum Dockerfile encontrado a partir de $(pwd)"
    exit 2
fi

echo "Config: $CONFIG"
echo

total_error=0
total_warning=0
total_info=0
total_style=0
total_politica=0
ausentes=0

conta_nivel() {
    # O JSON do hadolint é plano e estável ([{...},{...}]), então contar
    # ocorrências do campo dispensa jq/python sem ficar frágil.
    local json="$1" nivel="$2"
    printf '%s' "$json" | grep -o "\"level\":\"$nivel\"" | wc -l | tr -d ' '
}

# Checagem própria da skill: o estágio final declara um USER não-root?
#
# O DL3002 do hadolint só reprova quando o último USER é literalmente root. Um
# Dockerfile que simplesmente nunca declara USER passa limpo — e essa omissão é
# a forma mais comum de entregar um container rodando como root. Como esse é
# justamente o erro que a Fase 8 não pega (o container sobe, responde ao health
# e passa em todo curl do checklist), deixá-lo fora do gate esvaziaria o
# argumento da Fase 7.
#
# Só a omissão vira SKILL001. `USER root` explícito continua sendo assunto do
# DL3002, para o mesmo defeito não ser reportado duas vezes.
#
# Imprime "SEM_USER <linha>" quando falta, ou "OK".
checa_usuario_final() {
    awk '
        /^[[:space:]]*#/ {
            # Escape: `# skill ignore=SKILL001 # motivo` desliga a checagem no
            # arquivo — para o caso legítimo de a imagem base já rodar como
            # usuário sem privilégio (nginx-unprivileged, distroless nonroot).
            if ($0 ~ /skill[[:space:]]+ignore=SKILL001/) pragma = 1
            next
        }
        {
            linha = $0
            sub(/\r$/, "", linha)
            # Continuação de linha: acumula até a instrução terminar.
            if (linha ~ /\\[[:space:]]*$/) {
                sub(/\\[[:space:]]*$/, "", linha)
                buf = buf linha
                next
            }
            completa = buf linha
            buf = ""
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", completa)
            if (completa == "") next

            n = split(completa, tok, /[[:space:]]+/)
            inst = toupper(tok[1])

            if (inst == "FROM") {
                estagios++
                i = 2
                while (i <= n && tok[i] ~ /^--/) i++   # --platform=... e afins
                base[estagios] = tolower(tok[i])
                apelido[estagios] = ""
                if (n >= i + 2 && toupper(tok[i+1]) == "AS") apelido[estagios] = tolower(tok[i+2])
                usuario[estagios] = ""
                linha_from[estagios] = NR
            } else if (inst == "USER" && estagios > 0) {
                usuario[estagios] = tolower(tok[2])
            }
        }
        END {
            if (pragma || estagios == 0) { print "OK"; exit }
            s = estagios
            while (s > 0) {
                if (usuario[s] != "") { print "OK"; exit }
                # O estágio final pode ser construído sobre um estágio anterior
                # (FROM build), e nesse caso herda o USER dele.
                anterior = 0
                for (i = s - 1; i >= 1; i--)
                    if (apelido[i] != "" && apelido[i] == base[s]) { anterior = i; break }
                if (anterior == 0) break
                s = anterior
            }
            print "SEM_USER " linha_from[estagios]
        }
    ' "$1"
}

for arquivo in "${ARQUIVOS[@]}"; do
    if [[ ! -f "$arquivo" ]]; then
        echo "==> $arquivo"
        echo "    !! arquivo não encontrado"
        echo
        ausentes=$((ausentes + 1))
        continue
    fi

    echo "==> $arquivo"

    saida_tty="$(hadolint --no-fail --no-color -c "$CONFIG" -f tty "$arquivo" 2>&1)"
    saida_json="$(hadolint --no-fail -c "$CONFIG" -f json "$arquivo" 2>/dev/null)"

    achado_usuario="$(checa_usuario_final "$arquivo")"
    linha_politica=""
    if [[ "$achado_usuario" == SEM_USER* ]]; then
        linha_from="${achado_usuario#SEM_USER }"
        linha_politica="$arquivo:$linha_from SKILL001 política: Estágio final não declara USER — o processo roda como root (Fase 2, item 6)"
        total_politica=$((total_politica + 1))
    fi

    if [[ -z "$saida_tty" && -z "$linha_politica" ]]; then
        echo "    sem achados"
    else
        [[ -n "$saida_tty" ]] && printf '%s\n' "$saida_tty" | sed 's/^/    /'
        [[ -n "$linha_politica" ]] && printf '    %s\n' "$linha_politica"
    fi

    n_error=$(conta_nivel "$saida_json" error)
    n_warning=$(conta_nivel "$saida_json" warning)
    n_info=$(conta_nivel "$saida_json" info)
    n_style=$(conta_nivel "$saida_json" style)

    total_error=$((total_error + n_error))
    total_warning=$((total_warning + n_warning))
    total_info=$((total_info + n_info))
    total_style=$((total_style + n_style))

    echo
done

plural="arquivos"
[[ ${#ARQUIVOS[@]} -eq 1 ]] && plural="arquivo"
resumo="$total_error error, $total_warning warning, $total_politica política ($total_info info, $total_style style) em ${#ARQUIVOS[@]} $plural"

# Caminho inexistente bloqueia em vez de "pular": diferente do hadolint ausente,
# um path errado está inteiramente na sua mão e custa uma correção de segundos.
# Tratá-lo como PULADO faria um erro de digitação virar um Dockerfile entregue
# sem nunca ter passado pelo gate.
if [[ $ausentes -gt 0 ]]; then
    echo "LINT: BLOQUEADO — $ausentes caminho(s) inexistente(s); confira o path do Dockerfile e rode de novo"
    exit 1
fi

if [[ $total_error -gt 0 || $total_warning -gt 0 || $total_politica -gt 0 ]]; then
    echo "LINT: BLOQUEADO — $resumo"
    echo "   Resolva os achados error, warning e política antes de seguir para a"
    echo "   validação em runtime. O catálogo de regras e o que fazer com cada uma"
    echo "   está em $SKILL_DIR/references/lint.md"
    exit 1
fi

echo "LINT: OK — $resumo"
if [[ $total_info -gt 0 || $total_style -gt 0 ]]; then
    echo "   Achados info/style não bloqueiam, mas leia-os e mencione no relatório o"
    echo "   que você decidiu sobre cada um (references/lint.md explica os comuns)."
fi
exit 0
