#!/usr/bin/env bash

# ==============================================================================
# Script para migrar notas y writeups de Obsidian a Hugo (Tema Blowfish)
# - Copia las imágenes desde tus apuntes a la carpeta 'img/' del post.
# - Convierte los enlaces ![[imagen.png]] a ![](<img/imagen.png>)
# - Maneja nombres con espacios y modificadores de tamaño (|400).
# ==============================================================================

# Archivo a procesar (por defecto index.es.md si estás dentro de la carpeta del post)
MD_FILE="${1:-index.es.md}"

if [ ! -f "$MD_FILE" ]; then
    echo "❌ Error: El archivo '$MD_FILE' no existe."
    echo "Uso: $0 [ruta/al/archivo.md]"
    echo "Ejemplo: cd content/posts/mi-post && $0"
    echo "Ejemplo: $0 content/posts/mi-post/index.es.md"
    exit 1
fi

# Directorio del post y carpeta destino para imágenes
POST_DIR="$(cd "$(dirname "$MD_FILE")" && pwd)"
IMG_DIR="$POST_DIR/img"
mkdir -p "$IMG_DIR"

echo "📂 Procesando post en: $POST_DIR"
echo "📁 Carpeta de imágenes: $IMG_DIR"
echo "------------------------------------------------------------"

total=0
copiadas=0
faltantes=0

# Extraer todos los enlaces de imágenes de Obsidian
# Compatible con ![[archivo.png]] y ![[archivo.png|500]]
mapfile -t RAW_IMAGES < <(grep -oP '!\[\[\K[^\]]+(?=\]\])' "$MD_FILE" | sort -u)

for raw in "${RAW_IMAGES[@]}"; do
    [ -z "$raw" ] && continue
    total=$((total + 1))

    # Quitar cualquier modificador de tamaño como |300 o |center
    file="${raw%%|*}"

    # Si ya existe en la carpeta img/ local, no hace falta buscarla
    if [ -f "$IMG_DIR/$file" ]; then
        echo "✔️  Ya presente: $file"
        copiadas=$((copiadas + 1))
        continue
    fi

    # 1. Buscar en la ruta típica de Obsidian
    orig="$HOME/Documents/Apuntes/img/$file"

    if [ -f "$orig" ]; then
        cp "$orig" "$IMG_DIR/"
        echo "✅ Copiada de Apuntes/img: $file"
        copiadas=$((copiadas + 1))
    else
        # 2. Si no está en img/, buscar recursivamente en $HOME/Documents
        found=$(find "$HOME/Documents" -type f -name "$file" -print -quit 2>/dev/null)
        if [ -n "$found" ]; then
            echo "🔍 Encontrada en: $found"
            cp "$found" "$IMG_DIR/"
            copiadas=$((copiadas + 1))
        else
            echo "⚠️  No se encontró en ningún directorio: $file"
            faltantes=$((faltantes + 1))
        fi
    fi
done

echo "------------------------------------------------------------"
echo "🔄 Actualizando sintaxis de imágenes en '$MD_FILE'..."

# Reemplaza ![[archivo.png]] o ![[archivo.png|tamaño]] por ![](<img/archivo.png>)
sed -i -E 's/!\[\[([^]|]+)(\|[^]]*)?\]\]/![](<img\/\1>)/g' "$MD_FILE"

echo "✨ ¡Listo!"
echo "   - Total imágenes referenciadas: $total"
echo "   - Imágenes copiadas a ./img/:   $copiadas"
if [ "$faltantes" -gt 0 ]; then
    echo "   - Imágenes faltantes:          $faltantes"
fi

# Avisar si falta cabecera frontmatter
if ! head -n 1 "$MD_FILE" | grep -q "^---"; then
    echo ""
    echo "⚠️  AVISO: '$MD_FILE' no tiene cabecera frontmatter (---)."
    echo "   Recuerda añadir el título, fecha y tags al inicio del archivo."
fi
