#!/usr/bin/env bash

# ==============================================================================
# Script para migrar notas y writeups de Obsidian a Hugo (Tema Blowfish)
# Compatible al 100% con Linux y macOS (usa Python 3 disponible en ambos sistemas)
# - Copia las imágenes desde tus apuntes a la carpeta 'img/' del post.
# - Soporta enlaces Wiki ![[...]], etiquetas HTML <img src="..."> y Markdown ![](...)
# - Maneja nombres con espacios y modificadores de tamaño (|400, etc.).
# ==============================================================================

if command -v python3 >/dev/null 2>&1; then
    exec python3 - "$@" << 'EOF'
import os
import sys
import re
import shutil

target_arg = sys.argv[1] if len(sys.argv) > 1 else "index.es.md"
target_file = os.path.abspath(target_arg)

if not os.path.isfile(target_file):
    print(f"❌ Error: El archivo '{target_arg}' no existe.")
    print("Uso: import_obsidian.sh [ruta/al/archivo.md]")
    print("Ejemplo: cd content/posts/mi-post && ../../../scripts/import_obsidian.sh")
    print("Ejemplo: ./scripts/import_obsidian.sh content/posts/mi-post/index.es.md")
    sys.exit(1)

post_dir = os.path.dirname(target_file)
img_dir = os.path.join(post_dir, "img")
os.makedirs(img_dir, exist_ok=True)

print(f"📂 Procesando post en: {post_dir}")
print(f"📁 Carpeta de imágenes: {img_dir}")
print("-" * 60)

with open(target_file, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Extraer enlaces Wiki ![[...]]
matches_wiki = re.findall(r'!\[\[(.*?)\]\]', content)

# 2. Extraer etiquetas HTML <img ... src="..." ...>
matches_html = re.findall(r'<img[^>]+src=["\']([^"\']+)["\']', content)

# 3. Extraer Markdown estándar ![...](...)
matches_md = re.findall(r'!\[.*?\]\((.*?)\)', content)

unique_files = []

def add_clean_name(name):
    if not name:
        return
    name = name.strip()
    if name.startswith("<") and name.endswith(">"):
        name = name[1:-1].strip()
    name = name.split("?")[0].split("#")[0].strip()
    # Ignorar enlaces remotos de internet
    if name.startswith(("http://", "https://", "data:")):
        return
    # Si ya tiene prefijo img/, limpiarlo para buscar el archivo real
    if name.startswith("img/"):
        name = name[4:].strip()
    if name and name not in unique_files:
        unique_files.append(name)

for m in matches_wiki:
    add_clean_name(m.split('|')[0])

for m in matches_html + matches_md:
    add_clean_name(m.split('|')[0])

total = len(unique_files)
copiadas = 0
faltantes = 0

home = os.path.expanduser("~")
apuntes_img = os.path.join(home, "Documents", "Apuntes", "img")
docs_dir = os.path.join(home, "Documents")

for file_name in unique_files:
    dest_path = os.path.join(img_dir, file_name)
    if os.path.isfile(dest_path):
        print(f"✔️  Ya presente: {file_name}")
        copiadas += 1
        continue

    # 1. Buscar en ~/Documents/Apuntes/img/
    orig = os.path.join(apuntes_img, file_name)
    if os.path.isfile(orig):
        shutil.copy2(orig, dest_path)
        print(f"✅ Copiada de Apuntes/img: {file_name}")
        copiadas += 1
        continue

    # 2. Buscar recursivamente en ~/Documents/
    found = None
    for root, dirs, files in os.walk(docs_dir):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ('node_modules', 'public', 'resources')]
        if file_name in files:
            found = os.path.join(root, file_name)
            break

    if found:
        shutil.copy2(found, dest_path)
        print(f"🔍 Encontrada en: {found}")
        copiadas += 1
    else:
        print(f"⚠️  No se encontró en ningún directorio: {file_name}")
        faltantes += 1

print("-" * 60)
print(f"🔄 Actualizando sintaxis de imágenes en '{os.path.basename(target_file)}'...")

# Reemplaza ![[archivo.png]] por ![](<img/archivo.png>)
def repl_wiki(match):
    name = match.group(1).split('|')[0].strip()
    return f"![](<img/{name}>)"

content = re.sub(r'!\[\[([^]|]+)(?:\|[^]]*)?\]\]', repl_wiki, content)

# Actualiza <img src="archivo.png"> por <img src="img/archivo.png"> (si no es remoto y no tiene ya img/)
def repl_html(match):
    full = match.group(0)
    src = match.group(1).strip()
    if src.startswith(("http://", "https://", "data:", "img/")):
        return full
    return full.replace(f'src="{src}"', f'src="img/{src}"').replace(f"src='{src}'", f"src='img/{src}'")

content = re.sub(r'<img[^>]+src=["\']([^"\']+)["\']', repl_html, content)

with open(target_file, "w", encoding="utf-8") as f:
    f.write(content)

print("✨ ¡Listo!")
print(f"   - Total imágenes locales referenciadas: {total}")
print(f"   - Imágenes copiadas a ./img/:           {copiadas}")
if faltantes > 0:
    print(f"   - Imágenes faltantes:                  {faltantes}")

if not content.lstrip().startswith("---"):
    print("")
    print(f"⚠️  AVISO: '{os.path.basename(target_file)}' no tiene cabecera frontmatter (---).")
    print("   Recuerda añadir el título, fecha y tags al inicio del archivo.")
EOF
    exit 0
fi

echo "❌ Error: python3 es necesario pero no se encontró en el sistema."
exit 1
