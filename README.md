# winutils — Hadoop 3.4.1 pour Windows

Binaires et scripts de build pour `winutils.exe`, `hadoop.dll` et l'ensemble du dossier `bin/` Hadoop sur Windows.

Inspiré de [cdarlint/winutils](https://github.com/cdarlint/winutils) et [steveloughran/winutils](https://github.com/steveloughran/winutils), avec un pipeline de build reproductible basé sur [notepass/hadoop-native-win-libs](https://github.com/notepass/hadoop-native-win-libs) et la doc officielle [apache/hadoop BUILDING.txt](https://github.com/apache/hadoop/blob/rel/release-3.4.1/BUILDING.txt).

## Contenu de `hadoop-3.4.1/bin/`

| Fichier | Rôle |
|---------|------|
| `winutils.exe` | Utilitaire natif (permissions, symbolic links) — **obligatoire** pour Spark/Hadoop sur Windows |
| `hadoop.dll` | Bibliothèque native Hadoop — **obligatoire** |
| `hadoop.cmd`, `hdfs.cmd`, `yarn.cmd`, `mapred.cmd` | Wrappers Windows (mode `full` uniquement) |
| `hadoop`, `hdfs`, `yarn`, `mapred` | Scripts shell Git Bash |
| `*.lib`, `*.exp` | Artefacts de link (optionnels en runtime) |

## Utilisation sur Windows

```cmd
set HADOOP_HOME=C:\chemin\vers\hadoop-3.4.1
set PATH=%PATH%;%HADOOP_HOME%\bin
```

Cela corrige les erreurs `Could not locate Hadoop executable` et `NativeIO$Windows`.

---

## Build natif sur Windows

### Prérequis

- Windows 10/11
- **Visual Studio 2019 ou 2022** — workload « Desktop development with C++ »
- **JDK 8** (Azul Zulu ou OpenJDK recommandé)
- **Maven 3.8+**
- **CMake 3.19+**
- **Git for Windows** (bash requis pour l'emballage dist)
- Privilège « Create symbolic links » pour l'utilisateur de build

### Installation des dépendances natives (vcpkg)

Depuis une invite **x64 Native Tools Command Prompt for VS 2019/2022** :

```cmd
scripts\setup-vcpkg.cmd
```

Installe boost, protobuf 3.21, openssl et zlib aux versions attendues par Hadoop 3.4.1.

### Build complet en une commande

```cmd
scripts\build-all.cmd full
```

| Mode | Commande | Durée | Contenu |
|------|----------|-------|---------|
| `native` | `scripts\build-all.cmd native` | ~10 min | `winutils.exe`, `hadoop.dll` |
| `full` | `scripts\build-all.cmd full` | ~1-2 h | Dossier `bin/` complet (style cdarlint) |

### Build pas à pas

```cmd
call scripts\win-paths.cmd
scripts\clone-hadoop.cmd
scripts\build-full-dist.cmd
scripts\extract-to-winutils.cmd full
```

Adaptez les chemins dans `scripts\win-paths.cmd` (`JAVA_HOME`, `MAVEN_HOME`, `VCPKG_ROOT`, etc.).

---

## Build depuis CachyOS / Linux

Les binaires Windows **doivent** être compilés avec MSVC. Le Dockerfile Windows officiel de Hadoop (`Dockerfile_windows_10`) ne fonctionne **pas** sur Linux — il requiert un hôte Windows.

Deux options depuis CachyOS :

### Option A — GitHub Actions (recommandé)

Poussez ce dépôt sur GitHub, puis :

```bash
chmod +x scripts/build-from-linux.sh
./scripts/build-from-linux.sh trigger full    # lance le build sur windows-latest
./scripts/build-from-linux.sh status          # suivi
./scripts/build-from-linux.sh download        # récupère hadoop-3.4.1/bin/
```

Prérequis : `gh auth login` (`sudo pacman -S github-cli`).

### Option B — Téléchargement rapide (fallback)

En attendant votre propre build CI :

```bash
./scripts/download-binaries.sh notepass
```

Source : [notepass/hadoop-native-win-libs rel/release-3.4.1](https://github.com/notepass/hadoop-native-win-libs/releases/tag/rel/release-3.4.1) (build CI transparent, ~10 min).

> **Note :** le zip notepass contient les libs natives uniquement (`winutils.exe`, `hadoop.dll`). Pour les `.cmd` complets, utilisez le mode `full` via GitHub Actions ou un build Windows local.

---

## Compatibilité Windows SDK (GetFileInformationByName)

Les SDK Windows récents entrent en conflit avec le code `winutils` de Hadoop. Le script `scripts/apply-win-compat-shim.ps1` applique automatiquement le contournement documenté par [notepass](https://github.com/notepass/hadoop-native-win-libs) sans modifier les sources upstream.

---

## Structure du dépôt

```
hadoop-3.4.1/bin/          # Binaires finaux
scripts/
  win-paths.cmd            # Configuration environnement VS/Maven/vcpkg
  setup-vcpkg.cmd          # Installation dépendances natives
  clone-hadoop.cmd         # Clone apache/hadoop rel/release-3.4.1
  build-native-only.cmd    # Build rapide (native only)
  build-full-dist.cmd      # Build distribution complète
  extract-to-winutils.cmd  # Copie vers hadoop-3.4.1/bin
  build-all.cmd            # Orchestrateur Windows
  build-from-linux.sh      # Déclenchement CI depuis Linux
  download-binaries.sh     # Fallback téléchargement
  apply-win-compat-shim.ps1
.github/workflows/build-winutils.yml
```

---

## Références

- [cdarlint/winutils](https://github.com/cdarlint/winutils) — binaires pré-compilés (arrêté à 3.3.6)
- [steveloughran/winutils](https://github.com/steveloughran/winutils) — origine, processus de release signé
- [notepass/hadoop-native-win-libs](https://github.com/notepass/hadoop-native-win-libs) — CI transparente pour 3.4.x
- [GWToolboxpp build Wine](https://github.com/gwdevhub/GWToolboxpp#building-on-linux-docker--wine) — approche Docker+Wine+MSVC (non applicable au build Maven Hadoop complet)
